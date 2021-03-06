module ParticlesModule
!------------------------------------------------------------------------------
! Lagrangian Particle Method (LPM) version 2.0
!------------------------------------------------------------------------------
!> @file
!> Provides the primitive Particles data structure that defines the spatial discretization of LPM.
!
!> @author
!> Peter Bosler, Sandia National Laboratories Center for Computing Research
!
!> @defgroup Particles Particles module
!> @brief Provides a vectorized Particles data structure that defines the particles for LPM spatial discretization.
!> Particles are combined with the Field data structure to define scalar and vector fields over a spatial domain.
!> Particles may be combined with a mesh object (e.g., PolyMesh2d) or an unstructured data object (e.g., a quadtree)
!> to facilitate interpolation, differentiation, quadrature, etc.
!>
!> @{
!
!------------------------------------------------------------------------------
use NumberKindsModule
use OutputWriterModule
use LoggerModule

implicit none
private
public Particles
public New, Delete, Copy
public InsertParticle
public PhysCoord, LagCoord
public LogStats, PrintDebugInfo
public TotalArea, TotalVolume
public WriteVTKLagCoords, WriteVTKParticleArea, WriteVTKParticleVolume, WriteVTKPoints
public WriteParticlesToMatlab
public SortIncidentEdgesAtParticle
public MakeParticleActive, MakeParticlePassive
!
!----------------
! Types and module constants
!----------------
!

!> @class Particles
!> @brief Class used to define a spatial discretization that may move in physical space.  
!> This class should be extended for use in specific PDE applications with the inclusion of ::field objects. 
!>
type Particles
	real(kreal), pointer :: x(:)  => null() !< physical coordinate
	real(kreal), pointer :: y(:)  => null() !< physical coordinate
	real(kreal), pointer :: z(:)  => null() !< physical coordinate
	real(kreal), pointer :: x0(:) => null() !< Lagrangian coordinate
	real(kreal), pointer :: y0(:) => null() !< Lagrangian coordinate
	real(kreal), pointer :: z0(:) => null() !< Lagrangian coordinate
	real(kreal), pointer :: area(:) => null() !< area represented by each particle
	real(kreal), pointer :: volume(:) => null() !< volume represented by each particle
	integer(kint), pointer :: nEdges(:) => null() !< number of edges (if a mesh is used) incident to each particle
	integer(kint), pointer :: incidentEdges(:,:) => null() !< indices to ::edges incident on each particle (only if a mesh is used)
	real(kreal), pointer :: incidentAngles(:,:) => null() !< angles of indcidence for edges at each particle (only if a mesh is used)
	logical(klog), pointer :: isActive(:) => null() ! true if particle represents a leaf face or cell; corresponds to area, volume > 0
	logical(klog), pointer :: isPassive(:) => null() ! true if particle represents a leaf vertex
	integer(kint) :: N = 0				! N particles in computation
	integer(kint) :: N_Max = 0			! Max particles allowed in memory
	integer(kint) :: geomKind = 0		! geometry identifier e.g., numberkindsmodule::planar_geom
end type

!
!----------------
! Logging
!----------------
!
logical(klog), save :: logInit = .FALSE.
type(Logger) :: log
character(len=28), save :: logKey = 'ParticlesLog'
integer(kint), parameter :: logLevel = TRACE_LOGGING_LEVEL
character(len=MAX_STRING_LENGTH) :: logString
!
!----------------
! Interfaces
!----------------
!

!> @brief Allocates memory and initializes to null/zero a Particles object.
interface New
	module procedure NewPrivate
end interface

!> @brief Deletes a Particles object and frees its memory.
interface Delete
	module procedure DeletePrivate
end interface

!> @brief Copies (deep copy) one Particles object to another
interface Copy
	module procedure copyPrivate
end interface

!> @brief Outputs statistics about a Particles object to the console via a ::logger object.
interface LogStats
	module procedure LogStatsPrivate
end interface

!> @brief Prints detailed information about a Particles object to the console.
interface PrintDebugInfo
	module procedure PrintDebugPrivate
end interface

contains
!
!----------------
! Standard methods : Constructor / Destructor, Copy
!----------------
!
subroutine NewPrivate( self, nMax, geomKind )
	type(Particles), intent(out) :: self
	integer(kint), intent(in) :: nMax
	integer(kint), intent(in) :: geomKind
	
	if (.NOT. logInit ) call InitLogger(log, procRank)
	
	! error checking
	if ( nMax <= 0 ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL, logKey, " invalid nMax.")
		return
	endif
	if ( geomKind /= SPHERE_GEOM .AND. geomKind /= PLANAR_GEOM ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL, logKey, " invalid geometry.")
		return
	endif
	
	self%N_Max = nMax
	self%N = 0
	self%geomKind = geomKind
	allocate(self%x(nMax))
	self%x = 0.0_kreal
	allocate(self%y(nMax))
	self%y = 0.0_kreal
	allocate(self%x0(nMax))
	self%x0 = 0.0_kreal
	allocate(self%y0(nMax))
	self%y0 = 0.0_kreal
	if ( geomKind /= PLANAR_GEOM ) then
		allocate(self%z(nMax))
		self%z = 0.0
		allocate(self%z0(nMax))
		self%z0 = 0.0
	endif	

	if ( geomKind == EUCLIDEAN_3D ) then
		allocate(self%volume(nMax))
		self%volume = 0.0_kreal
	else
		allocate(self%area(nMax))
		self%area = 0.0_kreal
	endif
	
	allocate(self%isActive(nMax))
	self%isActive = .FALSE.
	allocate(self%isPassive(nMax))
	self%isPassive = .FALSE.
	
	allocate(self%nEdges(nMax))
	self%nEdges = 0
	allocate(self%incidentEdges(MAX_VERTEX_DEGREE,nMax))
	self%incidentEdges = 0
	allocate(self%incidentAngles(MAX_VERTEX_DEGREE,nMax))
	self%incidentAngles = 0.0_kreal
end subroutine

subroutine DeletePrivate(self)
	type(Particles), intent(inout) :: self
	if ( associated(self%x)) deallocate(self%x)
	if ( associated(self%y)) deallocate(self%y)
	if ( associated(self%x0)) deallocate(self%x0)
	if ( associated(self%y0)) deallocate(self%y0)
	if ( associated(self%incidentEdges)) deallocate(self%incidentEdges)
	if ( associated(self%incidentAngles)) deallocate(self%incidentAngles)
	if ( associated(self%nEdges)) deallocate(self%nEdges)
	if ( associated(self%isActive)) deallocate(self%isActive)
	if ( associated(self%isPassive)) deallocate(self%isPassive)
	if ( associated(self%volume)) deallocate(self%volume)
	if ( associated(self%area)) deallocate(self%area)
	if ( associated(self%z)) deallocate(self%z)
	if ( associated(self%z0)) deallocate(self%z0)
	self%N = 0
	self%N_Max = 0
	self%geomKind = 0
end subroutine

subroutine copyPrivate(self, other )
	type(Particles), intent(inout) :: self
	type(Particles), intent(in) :: other
	!
	integer(kint) :: i
	
	if ( self%N_Max < other%N ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL,logkey//" CopyParticles ERROR : ", " not enough memory.")
		return
	endif
	
	if ( associated(other%z) .AND. .NOT. associated(self%z) ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL,logkey//" CopyParticles ERROR : ", " dimension mismatch.")
		return
	endif

	if ( associated(other%area) .AND. .NOT. associated(self%area) ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL,logkey//" CopyParticles ERROR : ", " area array not allocated.")
		return
	endif
	
	if ( associated(other%volume) .AND. .NOT. associated(self%volume) ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL,logkey//" CopyParticles ERROR : ", " volume array not allocated.")
		return
	endif
	
	do i = 1, other%N
		self%x(i) = other%x(i)
		self%x0(i) = other%x0(i)
		self%y(i) = other%y(i)
		self%y0(i) = other%y0(i)
		self%nEdges(i) = other%nEdges(i)
		self%incidentEdges(:,i) = other%incidentEdges(:,i)
		self%incidentAngles(:,i) = other%incidentAngles(:,i)
		self%isActive(i) = other%isActive(i)
		self%isPassive(i) = other%isPassive(i)
	enddo
	do i = other%N+1, self%N_Max
		self%x(i) = 0.0_kreal
		self%x0(i) = 0.0_kreal
		self%y(i) = 0.0_kreal
		self%y0(i) = 0.0_kreal
		self%nEdges(i) = 0
		self%incidentEdges(:,i) = 0
		self%incidentAngles(:,i) = 0.0_kreal
		self%isActive(i) = .FALSE.
		self%isPassive(i) = .FALSE.
	enddo
	if ( associated(other%z) ) then
		do i = 1, other%N
			self%z(i) = other%z(i)
			self%z0(i) = other%z0(i)
		enddo
		do i = other%N+1, self%N_Max
			self%z(i) = 0.0_kreal
			self%z0(i) = 0.0_kreal
		enddo
	endif
	if ( associated(other%area)) then
		do i = 1, other%N
			self%area(i) = other%area(i)
		enddo
		do i = other%N+1, self%N_Max
			self%area(i) = 0.0_kreal
		enddo
	endif
	if ( associated(other%volume)) then
		do i = 1, other%N
			self%volume(i) = other%volume(i)
		enddo
		do i = other%N+1, self%N_Max
			self%volume(i) = 0.0_kreal
		enddo
	endif
	self%N = other%N
end subroutine

subroutine PrintDebugPrivate( self ) 
	type(Particles), intent(in) :: self
	integer(kint) :: i, j
	print *, "Particles DEBUG info : "
	print *, "particles.N = ", self%N
	print *, "particles.N_Max = ", self%N_Max
	print *, "PHYSICAL COORDINATES : "
	if ( .NOT. associated(self%z) ) then
		do i = 1, self%N_Max
			print *, self%x(i), "   ", self%y(i)
		enddo
	else
		do i = 1, self%N_Max
			print *, self%x(i), "   ", self%y(i), "   ", self%z(i)
		enddo
	endif
	print *, "LAGRANGIAN COORDINATES : "
	if ( .NOT. associated(self%z0) ) then
		do i = 1, self%N_Max
			print *, self%x0(i), "   ", self%y0(i)
		enddo
	else
		do i = 1, self%N_Max
			print *, self%x0(i), "   ", self%y0(i), "   ", self%z0(i)
		enddo
	endif
	if ( associated(self%area )) then
		print *, "particles.area = "
		do i = 1, self%N_Max
			print *, self%area(i)
		enddo
	endif
	if ( associated(self%volume )) then
		print *, "particles.volume = "
		do i = 1, self%N_Max
			print *, self%volume(i)
		enddo
	endif
	print *, "particles.nEdges = "
	do i = 1, self%N_Max
		print *, self%nEdges(i)
	enddo
	print *, "particles.incidentEdges = "
	do i = 1, self%N_Max
		do j = 1, size(self%incidentEdges,1)
			write(6,'(I6)',advance='NO') self%incidentEdges(j,i)
		enddo
		print *, " "
	enddo
	print *, " "
	print *, "particles.incidentAngles = "
	do i = 1, self%N_Max
		do j = 1, size(self%incidentAngles,1)
			write(6,'(F15.12)',advance='NO') self%incidentAngles(j,i)
		enddo
		print *, " "
	enddo
	print *, " "
	print *, "particles.isActive = "
	do i = 1, self%N_Max
		print *, self%isActive(i)
	enddo
	print *, "particles.isPassive = "
	do i = 1, self%N_Max
		print *, self%isPassive(i)
	enddo
end subroutine

!> @brief Writes VTK point data to a .vtk file in vtk legacy version 2.0 PolyData format.
!> Used for plotting with VTK C++ programs or ParaView.
!> @param self particles to output
!> @param fileunit integer fileunit of output file.
!> @param title title associated with this particle set.
subroutine WriteVTKPoints( self, fileunit, title )
	class(Particles), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	character(len=*), intent(in), optional :: title
	!
	integer(kint) :: j
	
	if ( present(title)) then
		call WriteVTKFileHeader(fileunit, title)
	else
		call WriteVTKFileHeader(fileunit)
	endif
	write(fileunit,'(A,I8,A)') "POINTS ", self%N, " double "
	if ( self%geomKind == PLANAR_GEOM ) then
		do j = 1, self%N
			write(fileunit,*) self%x(j), self%y(j), 0.0_kreal
		enddo
	else
		do j = 1, self%N
			write(fileunit,*) self%x(j), self%y(j), self%z(j)
		enddo
	endif
end subroutine

!> @brief Writes a particle set's Lagrangian coordinates to VTK PolyData Output
!> @param self
!> @param fileunit
subroutine WriteVTKLagCoords( self, fileunit )
	class(Particles), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	!
	integer(kint) :: j
	
	write(fileunit,'(A)') "SCALARS lagParam double 3"
	write(fileunit,'(A)') "LOOKUP_TABLE default"
	if ( self%geomKind == PLANAR_GEOM ) then
		do j = 1, self%N
			write(fileunit,*) self%x0(j), self%y0(j), 0.0_kreal
		enddo
	else
		do j = 1, self%N
			write(fileunit,*) self%x0(j), self%y0(j), self%z0(j)
		enddo
	endif
end subroutine

!> @brief Writes particle area to VTK PolyData Output
!> @param self
!> @param fileunit
subroutine WriteVTKParticleArea(self, fileunit )
	class(Particles), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	!
	integer(kint) :: j
	
	if ( .NOT. associated(self%area) ) then
		call LogMessage(log, WARNING_LOGGING_LEVEL, "WriteVKTParticleArea : "," area not allocated.")
		return
	endif
	do j = 1, self%N
		write(fileunit,*) self%area(j)
	enddo
end subroutine 

!> @brief Writes particle volume to VTK PolyData Output
!> @param self
!> @param fileunit
subroutine WriteVTKParticleVolume(self, fileunit )
	class(Particles), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	!
	integer(kint) :: j
	
	if ( .NOT. associated(self%volume) ) then
		call LogMessage(log, WARNING_LOGGING_LEVEL, "WriteVKTParticleVolume : "," volume not allocated.")
		return
	endif
	do j = 1, self%N
		write(fileunit,*) self%volume(j)
	enddo
end subroutine

!> @brief Inserts a single particle into a particles object.
!> @param physX physical coordinate vector
!> @param lagX Lagrangian coordinate vector
subroutine InsertParticle( self, physX, lagX )
	type(Particles), intent(inout) :: self
	real(kreal), intent(in) :: physX(:), lagX(:)
	
	if ( self%N >= self%N_Max ) then
		call LogMessage(log,ERROR_LOGGING_LEVEL,logKey," InsertParticle : out of memory.")
		return
	endif
	
	self%x( self%N + 1 ) = physx(1)
	self%y( self%N + 1 ) = physx(2)
	self%x0(self%N + 1 ) = lagX(1)
	self%y0(self%N + 1 ) = lagX(2)
	
	if ( self%geomKind /= PLANAR_GEOM ) then
		self%z( self%N + 1 ) = physx(3)
		self%z0(self%N + 1 ) = lagX(3)
	endif
	self%isPassive(self%N+1) = .TRUE.
	self%N = self%N + 1
end subroutine

!> @brief Changes a passive particle to an active particle. 
!> Area/volume must be set separately.
!> @param self
!> @param index index of particle to be changed.
subroutine MakeParticleActive( self, index ) 
	type(Particles), intent(inout) :: self
	integer(kint), intent(in) :: index
	if ( self%isActive(index) ) then
		call LogMessage(log, WARNING_LOGGING_LEVEL, logkey//" MakeParticleActive WARNING : ", "particle is already active.")
		return
	endif
	self%isActive(index) = .TRUE.
	self%isPassive(index) = .FALSE.
end subroutine

!> @brief Changes an active particle to a passive particle. 
!> Area/volume may be set to zero separately.
!> @param self
!> @param index index of particle to be changed.
subroutine MakeParticlePassive( self, index )
	type(Particles), intent(inout) :: self
	integer(kint), intent(in) :: index
	if ( self%isPassive(index) ) then
		write(logstring,'(A,I8,A)') " particle ", index, " is already passive."
		call LogMessage(log, WARNING_LOGGING_LEVEL, trim(logkey)//" MakeParticlePassive WARNING : ", logstring)
		return
	endif
	self%isPassive(index) = .TRUE.
	self%isActive(index) = .FALSE.
end subroutine

!> @brief Writes particles information to console using a loggermodule::logger object for formatting. 
!> @param self
!> @param aLog
subroutine LogStatsPrivate(self, aLog )
	type(Particles), intent(in) :: self
	type(Logger), intent(inout) :: aLog

	call LogMessage(aLog, TRACE_LOGGING_LEVEL, logKey, " Particles Stats : ")
	call StartSection(aLog)
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "particles.N = ", self%N )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "particles.N_Max = ", self%N_Max )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "max x = ", maxval(self%x) )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "min x = ", minval(self%x) )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "max y = ", maxval(self%y) )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "min y = ", minval(self%y) )
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "n active particles = ", count(self%isActive))
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "n passive particles= ", count(self%isPassive))
	if ( associated(self%area) ) then
		call LogMessage(aLog, TRACE_LOGGING_LEVEL, "max active particle area = ", maxval(self%area, MASK=self%isActive))
		call LogMessage(aLog, TRACE_LOGGING_LEVEL, "min active particle area = ", minval(self%area, MASK=self%isActive))
		call LogMessage(aLog, TRACE_LOGGING_LEVEL, "sum(particles.area) = ", sum(self%area(1:self%N)))
		call LogMessage(aLog, TRACE_LOGGING_LEVEL, "sum(active particles.area) = ", &
							sum(self%area(1:self%N), MASK=self%isActive(1:self%N)))
	endif
	call EndSection(aLog)
end subroutine

!> @brief Sorts the incident edges at a particle into counter-clockwise order using a bubble-sort algorithm.
!> @param self
!> @param index of particle whose edges need sorting.
subroutine SortIncidentEdgesAtParticle( self, index )
	type(Particles), intent(inout) :: self
	integer(kint), intent(in) :: index
	!
	integer(kint) :: i, j
	
	
	if ( self%nEdges(index) == 0 ) then
		write(logString,*) "no edges at particle ", index, "."
		call LogMessage(log, WARNING_LOGGING_LEVEL,"SortEdgesAtParticle : ",trim(logString))
		return
	endif
	if ( associated(self%area) ) then
		if ( self%area(index) > 0.0_kreal ) then
			call LogMessage(log, WARNING_LOGGING_LEVEL,"SortEdgesParticle : ", "vertices should have 0 area.")
			return
		endif
	endif
	if ( associated(self%volume) ) then
		if ( self%volume(index) > 0.0_kreal ) then
			call LogMessage(log, WARNING_LOGGING_LEVEL,"SortEdgesParticle : ", "vertices should have 0 volume.")
			return
		endif
	endif
	
!	print *, "particle ", index, ", nEdges = ", self%nEdges(index)
!	print *, "edges at particle = ", self%incidentEdges(1:self%nEdges(index), index)
	
	do i = 1, self%nEdges(index)
		do j = self%nEdges(index), i + 1, -1
			call OrderEdgePair(self%incidentEdges(j-1,index), self%incidentAngles(j-1,index), &
							   self%incidentEdges(j,index), self%incidentAngles(j,index) )
		enddo
	enddo
	
!	print *, "sorted edges at particle = ", self%incidentEdges(1:self%nEdges(index), index)
end subroutine

pure subroutine OrderEdgePair( index1, angle1, index2, angle2 )
	integer(kint), intent(inout) :: index1
	real(kreal), intent(inout) :: angle1
	integer(kint), intent(inout) :: index2
	real(kreal), intent(inout) :: angle2
	!
	integer(kint) :: tempIndex
	real(kreal) :: tempAngle
	if ( angle1 > angle2 ) then
		tempIndex = index1
		tempAngle = angle1
		index1 = index2
		angle1 = angle2
		index2 = tempIndex
		angle2 = tempAngle
	endif 	
end subroutine

!> @brief Returns a particle's physical coordinate vector
!> @param self
!> @param index
!> @return PhysCoord coordinate vector
pure function PhysCoord( self, index )
	real(kreal) :: PhysCoord(3)
	type(Particles), intent(in) :: self
	integer(kint), intent(in) :: index
	PhysCoord = 0.0_kreal
	PhysCoord(1) = self%x(index)
	PhysCoord(2) = self%y(index)
	if ( associated(self%z)) PhysCoord(3) = self%z(index)
end function

!> @brief Returns a particle's Lagrangian coordinate vector
!> @param self
!> @param index
!> @return LagCoord coordinate vector
pure function LagCoord( self, index )
	real(kreal) :: LagCoord(3)
	type(Particles), intent(in) :: self
	integer(kint), intent(in) :: index
	LagCoord = 0.0
	LagCoord(1) = self%x0(index)
	LagCoord(2) = self%y0(index)
	if ( associated(self%z0) ) LagCoord(3) = self%z0(index)
end function

!> @brief Returns the total area represented by all active ParticlesModule
!> @param self
!> @return TotalArea
pure function TotalArea( self ) 
	real(kreal) :: TotalArea
	type(Particles), intent(in) :: self
	TotalArea = sum(self%area(1:self%N), MASK=self%isActive(1:self%N) )	
end function

!> @brief Returns the total volume represented by all active ParticlesModule
!> @param self
!> @return Totalvolume
pure function TotalVolume(self)
	real(kreal) :: TotalVolume
	type(Particles), intent(in) :: self
	TotalVolume = sum(self%volume(1:self%N), MASK=self%isActive(1:self%N) )
end function


!> @brief Writes particles to a script .m file readable by Matlab
!> @param self
!> @param fileunit
subroutine WriteParticlesToMatlab( self, fileunit )
	type(Particles), intent(in) :: self
	integer(kint), intent(in) :: fileunit 
	!
	integer(kint) :: i
	
	write(fileunit,*) "x = [", self%x(1), ", ..."
	do i = 2, self%N-1
		write(fileunit,*) self%x(i), ", ..."
	enddo
	write(fileunit,*) self%x(self%N), "];"
	
	write(fileunit,*) "x0 = [", self%x0(1), ", ..."
	do i = 2, self%N-1
		write(fileunit,*) self%x0(i), ", ..."
	enddo
	write(fileunit,*) self%x0(self%N), "];"

	write(fileunit,*) "y = [", self%y(1), ", ..."
	do i = 2, self%N-1
		write(fileunit,*) self%y(i), ", ..."
	enddo
	write(fileunit,*) self%y(self%N), "];"
	
	write(fileunit,*) "y0 = [", self%y0(1), ", ..."
	do i = 2, self%N-1
		write(fileunit,*) self%y0(i), ", ..."
	enddo
	write(fileunit,*) self%y0(self%N), "];"	
	
	if ( self%geomKind /= PLANAR_GEOM ) then
		write(fileunit,*) "z = [", self%z(1), ", ..."
		do i = 2, self%N-1
			write(fileunit,*) self%z(i), ", ..."
		enddo
		write(fileunit,*) self%z(self%N), "];"

		write(fileunit,*) "z0 = [", self%z0(1), ", ..."
		do i = 2, self%N-1
			write(fileunit,*) self%z0(i), ", ..."
		enddo
		write(fileunit,*) self%z0(self%N), "];"
	endif
	
	if ( associated(self%area) ) then
		write(fileunit,*) "area = [", self%area(1), ", ..."
		do i = 2, self%N-1
			write(fileunit,*) self%area(i), ", ..."
		enddo
		write(fileunit, *) self%area(self%N), "];"
	endif
	
	if ( associated(self%volume) ) then
		write(fileunit,*) "volume = [", self%volume(1), ", ..."
		do i = 2, self%N-1
			write(fileunit,*) self%volume(i), ", ..."
		enddo
		write(fileunit, *) self%volume(self%N), "];"
	endif
end subroutine

subroutine InitLogger(aLog,rank)
! Initialize a logger for this module and processor
	type(Logger), intent(out) :: aLog
	integer(kint), intent(in) :: rank
	write(logKey,'(A,A,I0.3,A)') trim(logKey),'_',rank,' : '
	if ( rank == 0 ) then
		call New(aLog,logLevel)
	else
		call New(aLog,ERROR_LOGGING_LEVEL)
	endif
	logInit = .TRUE.
end subroutine

!>@}
end module
