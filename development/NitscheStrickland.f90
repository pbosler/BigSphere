program NitcheStrickland

use NumberKindsModule
use LoggerModule 
use PlanarSWEModule
use ParticlesModule
use FieldModule
use MPISetupModule
use SWEPlaneRK4Module
use PSEDirectSumModule

implicit none

include 'mpif.h'

!
!	computing environment
!
type(Logger) :: exeLog
character(len=MAX_STRING_LENGTH) :: logstring
character(len=15) :: logKey = "NS2002"
integer(kint), parameter :: logLevel = DEBUG_LOGGING_LEVEL
character(len=MAX_STRING_LENGTH) :: namelistFilename
integer(kint) :: mpiErrCode
real(kreal) :: programStart, programEnd
!
!	mesh variables
!
type(SWEMesh) :: mesh
integer(kint) :: meshSeed
integer(kint) :: faceKind
integer(kint) :: initNest
integer(kint) :: maxNest
integer(kint) :: amrLimit
real(kreal), parameter :: meshRadius = 10.0_kreal
real(kreal) :: f0 
real(kreal) :: beta 
real(kreal), parameter :: g = 1.0_kreal
character(len=MAX_STRING_LENGTH) :: meshString

namelist /meshDefine/ faceKind, initNest, maxNest, amrLimit, f0, beta
!
!	timestepping
!
type(SWEPlaneRK4) :: timekeeper
real(kreal) :: dt
real(kreal) :: tfinal
real(kreal) :: t
integer(kint) :: timeJ, nTimesteps
type(PSE) :: pseSetup

namelist /timestepping/ dt, tfinal
!
!	I/O variables
!
character(len=MAX_STRING_LENGTH) :: outputDir, outputRoot, vtkFile, matlabFile, vtkRoot
integer(kint) :: frameOut, frameCounter
namelist /fileIO/ outputDir, outputRoot, frameOut


!--------------------------------
!	initialize : setup computing environment
!--------------------------------
call MPI_INIT(mpiErrCode)
call MPI_COMM_SIZE(MPI_COMM_WORLD, numProcs, mpiErrCode)
call MPI_COMM_RANK(MPI_COMM_WORLD, procRank, mpiErrCode)
programStart = MPI_WTIME()

call InitLogger(exeLog, procRank)

call ReadNamelistFile(procRank)

!--------------------------------
!	initialize : setup problem / build mesh
!--------------------------------

call New(mesh, meshSeed, initNest, maxNest, amrLimit, meshRadius, f0, beta, g)
call SetInitialVorticityOnMesh( mesh, initVorticity )
call SetInitialDivergenceOnMesh( mesh, initDivergence)
call SetInitialVelocityOnMesh(mesh, initVelocity )
call SetInitialHOnMesh( mesh, initH )
call SetInitialDepthOnMesh( mesh, initDepth)
call SetInitialPotVortOnMesh( mesh )

call New(timekeeper, mesh)
nTimesteps = floor(tfinal/dt)
t = 0.0_kreal
frameCounter = 1
call New(pseSetup, mesh%mesh)

if ( procRank == 0 ) then
	call LogStats(mesh, exeLog)
	
	if ( meshSeed == TRI_HEX_SEED ) then
		write(meshString, '(A,I1,A)') '_triHex', initNest, '_'
	elseif ( meshSeed == QUAD_RECT_SEED ) then
		write(meshString, '(A,I1,A)') '_quadRect', initNest, '_'
	endif

	write(vtkRoot,'(4A)') trim(outputDir), '/vtkOut/', trim(outputRoot), trim(meshString)
	write(vtkFile,'(A,I0.4,A)') trim(vtkRoot), 0, '.vtk'
	
	call OutputToVTKFile(mesh, vtkFile)
	call LogMessage(exelog, TRACE_LOGGING_LEVEL, trim(logkey)//" t = ", t)
endif

!--------------------------------
!	run : evolve the problem in time (currently no remeshing)
!--------------------------------
do timeJ = 0, nTimesteps - 1
	
	call Timestep( timekeeper, mesh, dt, initDepth, DepthLaplacian, pseSetup, mesh%mpiParticles)
	
	t = real(timeJ+1,kreal) * dt
	mesh%mesh%t = t
	
	if ( procRank == 0 .AND. mod(timeJ+1, frameOut) == 0 ) then
		write(vtkFile,'(A,I0.4,A)') trim(vtkRoot), frameCounter, '.vtk'
		
		call OutputToVTKFile( mesh, vtkFile )
			
		frameCounter = frameCounter + 1
		call LogMessage(exelog, TRACE_LOGGING_LEVEL, trim(logkey)//" t = ", mesh%mesh%t)
	endif	
enddo



!--------------------------------
!	finalize : clean up
!--------------------------------

programEnd = MPI_WTIME()

write(logstring,'(A,F12.2,A)') "PROGRAM COMPLETE : elapsed time ", programEnd - programStart, " seconds."
call LogMessage(exelog, TRACE_LOGGING_LEVEL, trim(logkey)//" ", logString)

call Delete(pseSetup)
call Delete(timekeeper)
call Delete(mesh)

call MPI_FINALIZE(mpiErrCode)

contains

function initDivergence( x, y )
	real(kreal) :: initDivergence
	real(kreal), intent(in) :: x, y
	initDivergence = 0.0_kreal
end function 

function initVorticity( x, y)
	real(kreal) :: initVorticity
	real(kreal), intent(in) :: x, y
	!
	real(kreal) :: r2
	real(kreal), parameter :: b = 0.5_kreal
	r2 = x*x + y*y
	initVorticity = (3.0_kreal * sqrt(r2) /( r2 + ZERO_TOL * ZERO_TOL) - 2.0_kreal * b * sqrt(r2)) * r2 * exp(-b * r2)
end function 

function initVelocity(x, y)
	real(kreal) :: initVelocity(2)
	real(kreal), intent(in) :: x, y
	!
	real(kreal) :: utheta, r2, theta
	real(kreal), parameter :: b = 0.5_kreal
	
	r2 = x * x + y * y
	utheta = r2 * exp( - b * r2)
	theta = atan2(y,x)
	
	initVelocity(1) = - utheta * sin(theta)
	initVelocity(2) =   utheta * cos(theta)
end function 

function initH(x, y)
	real(kreal) :: initH
	real(kreal), intent(in) :: x, y
	initH = 1.0_kreal
end function

function initDepth(x,y)
	real(kreal) :: initDepth
	real(kreal), intent(in) :: x, y
	initDepth = 0.0_kreal
end function

function DepthLaplacian( x, y )
	real(kreal) :: DepthLaplacian
	real(kreal), intent(in) :: x, y
	DepthLaplacian = 0.0_kreal
end function

subroutine InitLogger(log, rank)
	type(Logger), intent(inout) :: log
	integer(kint), intent(in) :: rank
	if ( rank == 0 ) then
		call New(log, logLevel)
	else
		call New(log, ERROR_LOGGING_LEVEL)
	endif
	write(logKey,'(A,I0.2,A)') trim(logKey)//"_", rank, ":"
end subroutine

subroutine ReadNamelistFile(rank)
	integer(kint), intent(in) :: rank
	!
	integer(kint), parameter :: initBCAST_intSize = 5
	integer(kint), parameter :: initBCAST_realSize = 4
	integer(kint) :: readStat
	integer(kint) :: bcastIntegers(initBCAST_intSize)
	real(kreal) :: bcastReals(initBCAST_realSize)
	integer(kint) :: mpiErrCode
	
	if ( COMMAND_ARGUMENT_COUNT() /= 1 ) then
		call LogMessage(exeLog,ERROR_LOGGING_LEVEL, trim(logKey), " expected namelist file name as 1st argument.")
		stop
	endif
	
	if ( rank == 0 ) then
		call GET_COMMAND_ARGUMENT(1, namelistFilename)
		
		open( unit=READ_UNIT, file=namelistFilename, status='OLD', action='READ', iostat=readStat)
			if (readStat /= 0 ) then	
				call LogMessage(exeLog, ERROR_LOGGING_LEVEL, trim(logKey), " cannot read namelist file.")
				stop
			endif
			read(READ_UNIT, nml=meshDefine)
			rewind(READ_UNIT)
			read(READ_UNIT, nml=timestepping)
			rewind(READ_UNIT)
			read(READ_UNIT, nml=fileIO)		
			! namelist /meshDefine/ faceKind, initNest, maxNest, amrLimit	
			
			if ( faceKind == 3 ) then
				meshSeed = TRI_HEX_SEED
			elseif ( faceKind == 4 ) then
				meshSeed = QUAD_RECT_SEED
			else
				call LogMessage(exeLog, WARNING_LOGGING_LEVEL, trim(logKey)//" ReadNamelistFile WARNING :", &
					" invalid faceKind -- using triangles.")
				meshSeed = TRI_HEX_SEED
			endif
			
			if (amrLimit == 0) maxNest = initNest
			
			bcastIntegers(1) = meshSeed
			bcastIntegers(2) = initNest
			bcastIntegers(3) = maxNest
			bcastIntegers(4) = amrLimit
			bcastIntegers(5) = frameOut
			
			bcastReals(1) = dt
			bcastReals(2) = tfinal
			bcastReals(3) = f0
			bcastReals(4) = beta
		close(READ_UNIT)
	endif
	
	call MPI_BCAST(bcastIntegers, initBCAST_intSize, MPI_INTEGER, 0, MPI_COMM_WORLD, mpiErrCode)
	
	call MPI_BCAST(bcastReals, initBCAST_realSize, MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, mpiErrCode)
	
	meshSeed = bcastIntegers(1)
	initNest = bcastIntegers(2)
	maxNest = bcastIntegers(3)
	amrLimit = bcastIntegers(4)
	frameOut = bcastIntegers(5)
	
	dt = bcastReals(1)
	tfinal = bcastReals(2)
	f0 = bcastReals(3)
	beta = bcastReals(4)
end subroutine

end program