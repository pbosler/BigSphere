module SSRFPACKInterfaceModule
!------------------------------------------------------------------------------
! Lagrangian Particle / Panel Method - Spherical Model
!------------------------------------------------------------------------------
!
!> @author
!> Peter Bosler, Department of Mathematics, University of Michigan
!
!> @defgroup SSRFPACKInterface SSRFPACK Interface Module
!> Provides and object-oriented interface into the ssrfpack.f module @cite SSRFPACK .
!
!
! DESCRIPTION:
!> @file
!> Provides and object-oriented interface into the ssrfpack.f module.
!
!------------------------------------------------------------------------------
use NumberKindsModule
use LoggerModule
use SphereGeomModule
use PanelsModule, only : GetNTracer
use STRIPACKInterfaceModule

implicit none
private
public SSRFPACKData
public New, Delete
public SetSourceLagrangianParameter
public SetSourceAbsVort, SetSourceRelVort
public SetSourceTracer
public SetSourceVelocity
public SetSourceKineticEnergy
public SetSigmaTol
public SIGMA_FLAG, GRAD_FLAG
public InterpolateVector, InterpolateScalar, InterpolateTracer
public SetSourceH

!
!----------------
! Types and module constants
!----------------
!

type SSRFPACKData
	real(kreal), pointer :: data1(:) => null(), &	! Source data values
							data2(:) => null(), &	! Source data values
							data3(:) => null(), &	! Source data values
							grad1(:,:) => null(), &	! Estimated gradients of source data1
							grad2(:,:) => null(), & ! Estimated gradients of source data2
							grad3(:,:) => null(), & ! Estimated gradients of source data3
							sigma1(:) => null(), &	! Smoothing factors for source data1
							sigma2(:) => null(), &	! Smoothing factors for source data2
							sigma3(:) => null(), &		! Smoothing factors for source data3
							tracer(:,:) => null(), &	! tracer data values
							tracerGrad(:,:,:) => null(), & ! tracer gradient values
							sigmaTracer(:,:) => null() ! smoothing factors for tracers
	real(kreal) :: dSig1, &			! Maximum difference in smoothing factors for source data1
				   dSig2, &			! Maximum difference in smoothing factors for source data2
				   dSig3, &			! Maximum difference in smoothing factors for source data3
				   sigmaTol	= 0.01_kreal	! Tolerance for setting smoothing factors in SSRFPACK GETSIG subroutine
end type

integer(kint), parameter :: SIGMA_FLAG = 1,& ! Flag indicates smoothing parameters are pre-computed
						    GRAD_FLAG = 1	 ! Flag indicates gradient estimates are pre-computed
integer(kint), save :: startTriangle = 1	 ! Stores initial guesses for locating new points within a Delaunay triangulation.

interface SetSourceVelocity
	module procedure SetSourceVelocityFromMeshData
	module procedure SetSourceVelocityFromArrays
end interface

interface SetSourceH
	module procedure SetSourceHFromArrays
end interface

!
!----------------
! Logging
!----------------
!
logical(klog), save :: logInit = .FALSE.
type(Logger) :: log
character(len=28) :: logKey = 'SSRFPACK'
integer(kint), parameter :: logLevel = TRACE_LOGGING_LEVEL
character(len=28) :: formatString
character(len=128) :: logString
!
!----------------
! Interfaces
!----------------
!
interface New
	module procedure NewPrivate
	module procedure NewPrivateTracer
end interface

interface Delete
	module procedure DeletePrivate
end interface

contains
!
!----------------
! Standard methods : Constructor / Destructor
!----------------
!
subroutine NewPrivate(self,DelTri,interpVector)
!	Allocate memory for SSRFPACK interpolation source data associated with spherical Delaunay triangulation object DelTri.
	type(SSRFPACKData), intent(out) :: self
	type(STRIPACKData), intent(in) :: DelTri
	logical(klog), intent(in) :: interpVector
	integer(kint) :: n

	if ( .NOT. logInit ) call InitLogger(log,procRank)

	n = delTri%n

	if ( interpVector ) then
		allocate(self%data1(n))
		self%data1 = 0.0_kreal
		allocate(self%data2(n))
		self%data2 = 0.0_kreal
		allocate(self%data3(n))
		self%data3 = 0.0_kreal
		allocate(self%grad1(3,n))
		self%grad1 = 0.0_kreal
		allocate(self%grad2(3,n))
		self%grad2 = 0.0_kreal
		allocate(self%grad3(3,n))
		self%grad3 = 0.0_kreal
		allocate(self%sigma1(6*n-12))
		self%sigma1 = 0.0_kreal
		allocate(self%sigma2(6*n-12))
		self%sigma2 = 0.0_kreal
		allocate(self%sigma3(6*n-12))
		self%sigma3 = 0.0_kreal
		call LogMessage(log,DEBUG_LOGGING_LEVEL,logKey,' SSRFPACK allocated for vector interp.')
	else
		allocate(self%data1(n))
		self%data1 = 0.0_kreal
		allocate(self%grad1(3,n))
		self%grad1 = 0.0_kreal
		allocate(self%sigma1(6*n-12))
		self%sigma1 = 0.0_kreal
		call LogMessage(log,DEBUG_LOGGING_LEVEL,logKey,' SSRFPACK allocated for scalar interp.')
	endif

end subroutine

subroutine NewPrivateTracer(self,DelTri,nTracers)
!	Allocate memory for SSRFPACK interpolation source data associated with spherical Delaunay triangulation object DelTri.
	type(SSRFPACKData), intent(out) :: self
	type(STRIPACKData), intent(in) :: DelTri
	integer(kint), intent(in) :: nTracers
	integer(kint) :: n

	if ( .NOT. logInit ) call InitLogger(log,procRank)

	n = delTri%n

	allocate(self%tracer(n,nTracers))
	self%tracer = 0.0_kreal
	allocate(self%tracerGrad(3,n,nTracers))
	self%tracerGrad = 0.0_kreal
	allocate(self%sigmaTracer(6*n-12,nTracers))
	self%sigmaTracer = 0.0_kreal

	call LogMessage(log,DEBUG_LOGGING_LEVEL,logKey,' SSRFPACK allocated for tracer interp.')
end subroutine


subroutine DeletePrivate(self)
! 	Free memory associated with an instance of SSRFPACKData
	type(SSRFPACKData), intent(inout) :: self
	if (associated(self%data1)) then
		deallocate(self%data1)
		deallocate(self%sigma1)
		deallocate(self%grad1)
	endif
	if ( associated(self%data2) ) then
		deallocate(self%data2)
		deallocate(self%data3)
		deallocate(self%grad2)
		deallocate(self%grad3)
		deallocate(self%sigma2)
		deallocate(self%sigma3)
	endif
	if ( associated(self%tracer)) then
		deallocate(self%tracer)
		deallocate(self%tracerGrad)
		deallocate(self%sigmaTracer)
	endif
end subroutine

!
!----------------
! Public functions
!----------------
!
subroutine SetSigmaTol(self,newTol)
! Set tolerance for SSRFPACK smoothing parameter subroutines
	type(SSRFPACKData), intent(inout) :: self
	real(kreal), intent(in) :: newTol
	self%sigmaTol = newTol
end subroutine

subroutine SetSourceLagrangianParameter(self,delTri)
! Set the SSRFPACK source data for interpolation of Lagrangian parameter vectors.
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint) :: j, nActive, nParticles, errCode

	nActive = delTri%activePanels%N_Active
	nParticles = delTri%particles%N

	! Record source data values from source mesh
	do j=1,nActive
		self%data1(j) = delTri%activePanels%x0(1,j)
		self%data2(j) = delTri%activePanels%x0(2,j)
		self%data3(j) = delTri%activePanels%x0(3,j)
	enddo
	do j=1,nParticles
		self%data1(nActive + j ) = delTri%particles%x0(1,j)
		self%data2(nActive + j ) = delTri%particles%x0(2,j)
		self%data3(nActive + j ) = delTri%particles%x0(3,j)
	enddo

	! Estimate gradients at nodes of Delaunay triangulation
	do j=1,delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data2,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad2(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data3,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad3(:,j),errCode)
	enddo

	! Determine smoothing factors at each Delaunay node
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig x0 = ',self%dSig1)
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data2,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad2,self%sigmaTol,self%sigma2,self%dSig2,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig y0 = ',self%dSig2)
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data3,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad3,self%sigmaTol,self%sigma3,self%dSig3,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig z0 = ',self%dSig3)
end subroutine

subroutine SetSourceTracer(self,delTri)
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	!
	integer(kint) :: j, k, nActive, nParticles, errCode, nTracer


	nActive = delTri%activePanels%N_active
	nParticles = delTri%particles%N

	nTracer = GetNTracer(delTri%activePanels)

	! record source data values from source mesh
	do k=1,nTracer
		do j=1,nActive
			self%tracer(j,k) = delTri%activePanels%tracer(j,k)
		enddo
		do j=1,nParticles
			self%tracer(nActive+j,k) = delTri%particles%tracer(j,k)
		enddo
	enddo

	! estimate gradients at nodes of Delaunay graph
	do k=1,nTracer
		do j=1,delTri%n
			call GRADL(delTri%n, j, delTri%x, delTri%y, delTri%z, self%tracer(:,k), &
					   delTri%list, delTri%lptr, delTri%lend, self%tracerGrad(:,j,k), errCode)
		enddo
	enddo

	! find smoothing factors at each node of Delaunay graph
	do k=1, nTracer
		call GETSIG(delTri%n, delTri%x, delTri%y, delTri%z, self%tracer(:,k), &
				    delTri%list, delTri%lptr, delTri%lend, &
				    self%tracerGrad(:,:,k), self%sigmaTol, self%sigmaTracer(:,k), self%dSig1, errCode)
	enddo

end subroutine

subroutine SetSourceVelocityFromMeshData(self,delTri)
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint) :: j, nActive, nParticles, errCode

	nActive = delTri%activePanels%N_Active
	nParticles = delTri%particles%N

	! record source data values from source mesh
	do j=1,nActive
		self%data1(j) = delTri%activePanels%u(1,j)
		self%data2(j) = delTri%activePanels%u(2,j)
		self%data3(j) = delTri%activePanels%u(3,j)
	enddo
	do j=1,nParticles
		self%data1(j) = delTri%particles%u(1,j)
		self%data2(j) = delTri%particles%u(2,j)
		self%data3(j) = delTri%particles%u(3,j)
	enddo

	! Estimate gradients at nodes of Delaunay triangulation
	do j=1,delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data2,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad2(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data3,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad3(:,j),errCode)
	enddo

	! Determine smoothing factors at each Delaunay node
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig u = ',self%dSig1)
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data2,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad2,self%sigmaTol,self%sigma2,self%dSig2,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig v = ',self%dSig2)
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data3,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad3,self%sigmaTol,self%sigma3,self%dSig3,errCode)
	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig w = ',self%dSig3)
end subroutine

subroutine SetSourceVelocityFromArrays(self, delTri, particlesVelocity, nParticles, activePanelsVelocity, nActive)
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	real(kreal), intent(in) :: particlesVelocity(:,:), activePanelsVelocity(:,:)
	integer(kint), intent(in) :: nParticles, nActive
	!
	integer(kint) :: j, errCode

	call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'entering SetSourceVelocityFromArrays...')

	do j=1, nActive
		self%data1(j) = activePanelsVelocity(1,j)
		self%data2(j) = activePanelsVelocity(2,j)
		self%data3(j) = activePanelsVelocity(3,j)
	enddo

	do j=1, nParticles
		self%data1(nActive + j) = particlesVelocity(1,j)
		self%data2(nActive + j) = particlesVelocity(2,j)
		self%data3(nActive + j) = particlesVelocity(3,j)
	enddo

	call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'...velocity data copied. estimating gradients.')

	do j=1, delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data2,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad2(:,j),errCode)
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data3,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad3(:,j),errCode)
	enddo

	call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'...gradients done.')

! Determine smoothing factors at each Delaunay node
!	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
!				delTri%list,delTri%lptr,delTri%lend,&
!			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
!	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig u = ',self%dSig1)
!	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data2,&
!				delTri%list,delTri%lptr,delTri%lend,&
!			    self%grad2,self%sigmaTol,self%sigma2,self%dSig2,errCode)
!	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig v = ',self%dSig2)
!	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data3,&
!				delTri%list,delTri%lptr,delTri%lend,&
!			    self%grad3,self%sigmaTol,self%sigma3,self%dSig3,errCode)
!	if ( procRank == 0 ) call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig w = ',self%dSig3)
end subroutine

subroutine SetSourceHFromArrays(self, delTri, particlesH, nParticles, activePanelsH, nActive)
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	real(kreal), intent(in) :: particlesH(:), activePanelsH(:)
	integer(kint), intent(in) :: nParticles, nActive
	!
	integer(kint) :: j, errCode

	call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'entering SetSourceHFromArrays.')

	do j=1, nActive
		self%data1(j) = activePanelsH(j)
	enddo

	do j=1, nParticles
		self%data1(nActive + j) = particlesH(j)
	enddo
		call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'...h data copied. estimating gradients.')
	do j=1, delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
	enddo
	call LogMessage(log,DEBUG_LOGGING_LEVEL,logkey,'...gradients done. finding smoothing factors.')
	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	call LogMessage(log,DEBUG_LOGGING_LEVEL,'SSRFPACK : dSig H = ',self%dSig1)
end subroutine

subroutine SetSourceAbsVort(self,delTri)
! Setup SSRFPACK to interpolate scalar absolute vorticity data
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint) :: j, nActive, nParticles, errCode

	nActive = delTri%activePanels%N_Active
	nParticles = delTri%particles%N

	do j=1,nActive
		self%data1(j) = delTri%activePanels%absVort(j)
	enddo

	do j=1,nParticles
		self%data1(nActive + j ) = delTri%particles%absVort(j)
	enddo

	do j=1,delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
	enddo

	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	call LogMessage(log,TRACE_LOGGING_LEVEL,'SSRFPACK : dSig absVort = ',self%dSig1)
end subroutine


subroutine SetSourceRelVort(self,delTri)
! Setup SSSRFPACK to interpolate scalar relative vorticity data
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint) :: j, nActive, nParticles, errCode

	nActive = delTri%activePanels%N_Active
	nParticles = delTri%particles%N

	do j=1,nActive
		self%data1(j) = delTri%activePanels%relVort(j)
	enddo

	do j=1,nParticles
		self%data1(nActive + j ) = delTri%particles%relVort(j)
	enddo

	do j=1,delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
	enddo

	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	!call LogMessage(log,TRACE_LOGGING_LEVEL,'SSRFPACK : dSig relVort = ',self%dSig1)
end subroutine



!subroutine SetSourceEnergy(self,delTri)
!	type(SSRFPACKData), intent(inout) :: self
!	type(STRIPACKData), intent(in) :: delTri
!	integer(kint) :: j, nActive, nParticles, errCode
!
!	if ( (.NOT. associated(delTri%activePanels%energy) ).OR. (.NOT. associated(delTri%particles%energy) ) ) then
!		call LogMessage(log,ERROR_LOGGING_LEVEL,trim(logKey),' SetSourceEnergy ERROR : energy not defined.')
!		return
!	endif
!
!	nActive = delTri%activePanels%N_Active
!	nParticles = delTri%particles%N
!
!	do j=1,nActive
!		self%data1(j) = delTri%activePanels%energy(j)
!	enddo
!
!	do j=1,nParticles
!		self%data1(nActive+j) = delTri%particles%energy(j)
!	enddo
!
!	do j=1,delTri%n
!		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
!				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
!	enddo
!
!	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
!				delTri%list,delTri%lptr,delTri%lend,&
!			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
!	call LogMessage(log,TRACE_LOGGING_LEVEL,'SSRFPACK : dSig relVort = ',self%dSig1)
!
!end subroutine

subroutine SetSourceKineticEnergy(self,delTri)
	type(SSRFPACKData), intent(inout) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint) :: j, nActive, nParticles, errCode

	if ( (.NOT. associated(delTri%activePanels%ke) ).OR. (.NOT. associated(delTri%particles%ke) ) ) then
		call LogMessage(log,ERROR_LOGGING_LEVEL,trim(logKey),' SetSourceKineticEnergy ERROR : KE not defined.')
		return
	endif

	nActive = delTri%activePanels%N_Active
	nParticles = delTri%particles%N

	do j=1,nActive
		self%data1(j) = delTri%activePanels%ke(j)
	enddo

	do j=1,nParticles
		self%data1(nActive+j) = delTri%particles%ke(j)
	enddo

	do j=1,delTri%n
		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
	enddo

	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend,&
			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
	call LogMessage(log,TRACE_LOGGING_LEVEL,'SSRFPACK : dSig relVort = ',self%dSig1)

end subroutine

!subroutine SetSourceTracer(self,delTri,tracerNumber)
!! Setup SSRFPACK to interpolate scalar tracer data
!	type(SSRFPACKData), intent(inout) :: self
!	type(STRIPACKData), intent(in) :: delTri
!	integer(kint), intent(in) :: tracerNumber
!	integer(kint) :: j, nActive, nParticles, errCode
!
!	nActive = delTri%activePanels%N_Active
!	nParticles = delTri%particles%N
!
!	do j=1,nActive
!		self%data1(j) = delTri%activePanels%tracer(j,tracerNumber)
!	enddo
!
!	do j=1,nParticles
!		self%data1(nActive + j ) = delTri%particles%tracer(j,tracerNumber)
!	enddo
!
!	call LogMessage(log,DEBUG_LOGGING_LEVEL,'SetSourcTracer : ','data set. Estimating gradients.')
!
!	do j=1,delTri%n
!		call GRADL(delTri%n,j,delTri%x,delTri%y,delTri%z,self%data1,&
!				   delTri%list,delTri%lptr,delTri%lend,self%grad1(:,j),errCode)
!	enddo
!
!	call LogMessage(log,DEBUG_LOGGING_LEVEL,'SetSourcTracer : ','gradients done. Finding smoothing factors.')
!
!	call GETSIG(delTri%n,delTri%x,delTri%y,delTri%z,self%data1,&
!				delTri%list,delTri%lptr,delTri%lend,&
!			    self%grad1,self%sigmaTol,self%sigma1,self%dSig1,errCode)
!	write(logString,'(A,I1,A)') 'SSRFPACK : dSig Tracer',tracerNumber,' = '
!	call LogMessage(log,TRACE_LOGGING_LEVEL,trim(logString),self%dSig1)
!end subroutine


function InterpolateVector(xyz,self,delTri)
!	Interpolate (using SSRFPACK) vector source data from self and delTri to value
!	at destination point xyz.
!
	real(kreal) :: InterpolateVector(3)
	real(kreal), intent(in) :: xyz(3)
	type(SSRFPACKData), intent(in) :: self
	type(STRIPACKData), intent(in) :: delTri
	real(kreal) :: newLat, newLon, newVector(3)
	integer(kint) :: errCode


	newLat = Latitude(xyz)
	newLon = Longitude(xyz)
	startTriangle = 1
	call INTRC1(delTri%n,newLat,newLon,delTri%x,delTri%y,delTri%z,self%data1, &
			    delTri%list,delTri%lptr,delTri%lend, &
			    SIGMA_FLAG,self%sigma1,GRAD_FLAG,self%grad1,startTriangle,&
			    newVector(1),errCode)
	call INTRC1(delTri%n,newLat,newLon,delTri%x,delTri%y,delTri%z,self%data2, &
			delTri%list,delTri%lptr,delTri%lend, &
			SIGMA_FLAG,self%sigma2,GRAD_FLAG,self%grad2,startTriangle,&
			newVector(2),errCode)
	call INTRC1(delTri%n,newLat,newLon,delTri%x,delTri%y,delTri%z,self%data3, &
			delTri%list,delTri%lptr,delTri%lend, &
			SIGMA_FLAG,self%sigma3,GRAD_FLAG,self%grad3,startTriangle,&
			newVector(3),errCode)
	InterpolateVector = newVector
end function


function InterpolateScalar(xyz,self,delTri)
!	Interpolate (using SSRFPACK) scalar source data from self and delTri to value
!	at destination point xyz.
!
	real(kreal) :: InterpolateScalar
	real(kreal), intent(in) :: xyz(3)
	type(SSRFPACKData), intent(in) :: self
	type(STRIPACKData), intent(in) :: delTri
	real(kreal) :: newLat, newLon, newScalar
	integer(kint) :: errCode

	newLat = Latitude(xyz)
	newLon = Longitude(xyz)
	call INTRC1(delTri%n,newLat,newLon,delTri%x,delTri%y,delTri%z,self%data1,&
				delTri%list,delTri%lptr,delTri%lend, &
				SIGMA_FLAG,self%sigma1,GRAD_FLAG,self%grad1,startTriangle,&
				newScalar,errCode)
	InterpolateScalar = newScalar
end function

function InterpolateTracer(xyz,self,delTri, tracerID)
!	Interpolate (using SSRFPACK) scalar source data from self and delTri to value
!	at destination point xyz.
!
	real(kreal) :: InterpolateTracer
	real(kreal), intent(in) :: xyz(3)
	type(SSRFPACKData), intent(in) :: self
	type(STRIPACKData), intent(in) :: delTri
	integer(kint), intent(in) :: tracerID
	real(kreal) :: newLat, newLon, newScalar
	integer(kint) :: errCode

	newLat = Latitude(xyz)
	newLon = Longitude(xyz)
	call INTRC1(delTri%n,newLat,newLon,delTri%x,delTri%y,delTri%z,self%tracer(:,tracerID),&
				delTri%list,delTri%lptr,delTri%lend, &
				SIGMA_FLAG,self%sigmaTracer(:,tracerID),GRAD_FLAG,self%tracerGrad(:,:,tracerID),startTriangle,&
				newScalar,errCode)
	InterpolateTracer = newScalar
end function

!
!----------------
! Module methods : type-specific functions
!----------------
!
subroutine InitLogger(aLog,rank)
	type(Logger), intent(inout) :: aLog
	integer(kint), intent(in) :: rank
	write(logKey,'(A,A,I0.2,A)') trim(logKey),'_',rank,' : '
	call New(aLog,logLevel)
	logInit = .TRUE.
end subroutine

end module
