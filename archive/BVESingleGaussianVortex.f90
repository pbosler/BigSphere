program BVEGaussVort
!******************************************************************************
!	Peter A. Bosler
!	Department of Mathematics
!	University of Michigan
!	pbosler@umich.edu
!
!******************************************************************************
!
!	This program solves the barotropic vorticity equation for the case of single Gaussian vortex on the sphere.
!
!	Bosler, P.A., "Particle Methods for Geophysical Flow on the Sphere," PhD Thesis; the University of Michigan, 2013.
!
!----------------
use NumberKindsModule
use OutputWriterModule
use LoggerModule
use SphereMeshModule
use RefineRemeshModule
use TracerSetupModule
use VTKOutputModule
use BVESetupModule
use BVEDirectSumModule
use ReferenceSphereModule

implicit none

include 'mpif.h'

!
!	mesh variables
!
type(SphereMesh) :: sphere
integer(kint) :: panelKind, initNest, AMR, nTracer, problemKind
!
!	time stepping variables
!
type(BVERK4Data) :: bveRK4
real(kreal) :: t, dt, tfinal
integer(kint) :: timesteps, timeJ
!
!	tracer variables
!
type(tracerSetup) :: cosBell
real(kreal) :: h0, RR, lat0, lon0
integer(kint) :: tracerID
real(kreal), allocatable :: massIntegral(:)
!
!	vorticity variables
!
type(BVESetup) :: gaussVort
real(kreal) :: vortLat, vortLon, bb, maxVort
real(kreal), allocatable :: totalKE(:), totalEns(:)
!
!	refinement variables
!
type(RefinementSetup) :: tracerRefine
real(kreal) :: tracerMaxTol, tracerVarTol
integer(kint) :: refinementLimit

type(RefinementSetup) :: vortRefine
real(kreal) :: circMaxTol, vortVarTol

type(RefinementSetup) :: flowMapRefine
real(kreal) :: lagVarTol

!
!	remeshing variables
!
integer(kint) :: remeshInterval, remeshCounter, resetAlpha
type(ReferenceSphere) :: refSphere
logical(klog) :: refSphereReady
!
!	User input
!
character(len = 128) :: namelistInputFile = 'gaussianVortex.namelist'
integer(kint) :: readStat
!
!	Output variables
!
type(VTKSource) :: vtkOut
character(len = 128) :: vtkRoot, vtkFile, outputDir, jobPrefix
character(len = 128) :: conservedDataFile, summaryFile
character(len = 56 ) :: amrString
integer(kint) :: frameCounter, frameOut, writeStat1, writeStat2
type(OutputWriter) :: writer
!
!	logging
!
type(Logger) :: exeLog
character(len=28) :: logKey
character(len=128) :: logString
!
!	general and mpi variables
!
integer(kint) :: i, j, k
integer(kint) :: mpiErrCode
integer(kint), parameter  :: BROADCAST_INT_SIZE = 6, BROADCAST_REAL_SIZE = 11
integer(kint) :: broadcastIntegers(BROADCAST_INT_SIZE)
real(kreal) :: broadcastReals(BROADCAST_REAL_SIZE)
real(kreal) :: wallClock

namelist /sphereDefine/ panelKind, initNest, AMR, tracerMaxTol, tracerVarTol, &
						refineMentLimit, circMaxTol, vortVarTol, lagVarTol
namelist /vorticityDefine/ 	vortLat, vortLon, bb, maxVort
namelist /timeStepping/ tfinal, dt,  remeshInterval, resetAlpha
namelist /fileIO/ outputDir, jobPrefix, frameOut

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	PROGRAM START
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
call MPI_INIT(mpiErrCode)
call MPI_COMM_SIZE(MPI_COMM_WORLD,numProcs,mpiErrCode)
call MPI_COMM_RANK(MPI_COMM_WORLD,procRank,mpiErrCode)

call InitLogger(exeLog,procRank)

wallClock = MPI_WTIME()

!
!	read user input from namelist file, broadcast to all processes
!
call ReadNameListFile(procRank)
call MPI_BCAST(broadcastIntegers,BROADCAST_INT_SIZE,MPI_INTEGER,0,MPI_COMM_WORLD,mpiErrCode)
panelKind = broadcastIntegers(1)
AMR = broadcastIntegers(2)
initNest = broadcastIntegers(3)
refinementLimit = broadcastIntegers(4)
remeshInterval = broadcastIntegers(5)
resetAlpha = broadcastIntegers(6)

call MPI_BCAST(broadcastReals,BROADCAST_REAL_SIZE,MPI_DOUBLE_PRECISION,0,MPI_COMM_WORLD,mpiErrCode)
tracermaxTol = broadcastReals(1)
tracerVarTol = broadcastReals(2)
tfinal = broadcastReals(3)*ONE_DAY ! convert tfinal to seconds
circMaxTol = broadcastReals(4)
vortVarTol = broadcastReals(5)
dt = broadcastReals(6) * ONE_DAY
lagVarTol = broadcastReals(7)
vortLat = broadcastReals(8)
vortLon = broadcastReals(9)
bb = broadcastReals(10)
maxVort = broadcastReals(11)*OMEGA

refSphereReady = .FALSE.

!
!	define test case
!
problemKind = BVE_SOLVER
nTracer = 3
h0 = 1000.0_kreal	! height of cosine bell center
lat0 = 0.0_kreal	! latitude of cosine bell center
lon0 = 0.0_kreal ! longitude of cosine bell center
RR = EARTH_RADIUS/3.0_kreal ! radius of cosine bell
tracerID = 1
call New(cosBell, COS_BELL_NINT, COS_BELL_NREAL)
call InitCosineBellTracer(cosBell,lat0,lon0,RR,h0,tracerID)

call New(gaussVort,SINGLE_VORTEX_NINT,SINGLE_VORTEX_NREAL)
call InitSingleGaussianVortex(gaussVort,vortLat,vortLon,bb,maxVort)

!
!	initialize sphere
!
call New(sphere,panelKind,initNest,AMR,nTracer,problemKind)
call SetCosineBellTracerOnMesh(sphere,cosBell)
call SetFlowMapLatitudeTracerOnMesh(sphere,2)
call SetFlowMapLatitudeTracerOnMesh(sphere,3)
call SetSingleGaussianVortexOnMesh(sphere,gaussVort)
if ( AMR > 0 ) then

	call New(tracerRefine,refinementLimit,tracermaxTol,tracerVarTol,TRACER_REFINE,tracerID)
	call SetRelativeTracerTols(sphere,tracerRefine)

	call New(vortRefine,refinementLimit,circMaxTol,vortVarTol,RELVORT_REFINE)
	call SetRelativeVorticityTols(sphere,vortRefine)

	call New(flowMapREfine,refinementLimit,100000.0_kreal,lagVarTol,FLOWMAP_REFINE)
	call SetRelativeFlowMapTol(sphere,flowMapRefine)

	!
	!	initial refinement
	!
	call InitialRefinement(sphere,tracerRefine,SetCosineBellTracerOnMesh, cosBell, &
						   vortRefine, SetSingleGaussianVortexOnMesh,gaussVort)

	call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' initial refinement done.')




	if ( panelKind == QUAD_PANEL) then
		write(amrString,'(A,I1,A,I0.2,A)') 'quadAMR_',initNest,'to',initNest+refinementLimit,'_'
	endif
else ! uniform mesh
	! nullify AMR variables
	call New(tracerRefine)
	call New(vortRefine)
	call New(flowMapRefine)
	if ( panelKind == QUAD_PANEL ) then
		write(amrString,'(A,I1,A)') 'quadUnif',initNest,'_'
	endif
endif

call SetFlowMapLatitudeTracerOnMesh(sphere,2)
call SetFlowMapLatitudeTracerOnMesh(sphere,3)

!
!	initialize output, output t = 0 data
!
frameCounter = 0
if ( procRank == 0 ) then
	call LogStats(sphere,exeLog,'initial mesh :')
	write(vtkRoot,'(A,A,A,A,A)') trim(outputDir), '/vtkOut/',trim(jobPrefix),trim(amrString),'_'
	write(vtkFile,'(A,I0.4,A)') trim(vtkRoot),frameCounter,'.vtk'

	call New(vtkOut,sphere,vtkFile,'gaussVort')
	call VTKOutput(vtkOut,sphere)
	frameCounter = frameCounter + 1
endif
!
!	intialize timestepping
!
call New(bveRK4,sphere,numProcs)
timesteps = floor(tfinal/dt)
t = 0.0_kreal
remeshCounter = 0

allocate(totalKE(0:timesteps))
allocate(totalEns(0:timesteps))
allocate(massIntegral(0:timesteps))
totalKE = 0.0_kreal
totalEns = 0.0_kreal
massIntegral = 0.0_kreal

massIntegral(0) = TotalMass(sphere,1)
totalEns(0) = TotalEnstrophy(sphere)

call StartSection(exeLog,'initial setup complete:')
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,'initial Rossby number : ',GetRossbyNumber(sphere) )
call EndSection(exeLog)

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	RUN THE PROBLEM
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
do timeJ = 0, timesteps - 1
	!
	!	remesh if necessary
	!
	if ( mod(timeJ+1,remeshInterval) == 0 ) then
		remeshCounter = remeshCounter + 1
		!
		!	delete objects associated with old mesh
		!
		call Delete(bveRK4)
		call Delete(vtkOut)
		!
		! build new mesh
		!
		if (remeshCounter < resetAlpha ) then
			call LagrangianRemesh(sphere, SetSingleGaussianVortexOnMesh, gaussVort, vortRefine, &
										  SetCosineBellTracerOnMesh, cosBell, tracerRefine, &
										  flowMapRefine)
			call SetFlowMapLatitudeTracerOnMesh(sphere,2)
			call SetFlowMapLatitudeTracerOnMesh(sphere,3)
		elseif ( mod(remeshCounter,resetAlpha) == 0 ) then

			call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' developing new mapping time.')

			if ( refSphereReady ) then
				call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' deleting reference sphere.')
				call Delete(refSphere)
				refSphereReady = .FALSE.
			endif

			call New(refSphere,sphere)
			refSphereReady = .TRUE.
			call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' reference sphere returned.')

			flowMapRefine%type = NULL_REFINE
			call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' flowMap refinement nullified.')

			call ResetLagrangianParameter(sphere)
			call LagrangianRemesh(sphere,refSphere,vortRefine,tracerRefine,flowMapRefine)


  		    call ResetLagrangianParameter(sphere)
  		    flowMapRefine%type = FLOWMAP_REFINE

!			if ( procRank == 0 .AND. mod(timeJ+1,frameOUt) == 0  ) then
!				call LogMessage(exeLog,TRACE_LOGGING_LEVEL,'day = ',t/ONE_DAY)
!				write(vtkFile,'(A,A,A)') trim(vtkRoot), 'NEW', '.vtk'
!				call UpdateFileName(vtkOut,vtkFile)
!				call VTKOutput(vtkOut,sphere)
!				frameCounter = frameCounter + 1
!			endif

			call SetFlowMapLatitudeTracerOnMesh(sphere,3)

		    call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logkey,'RESET LAGRANGIAN PARAMETER')

		else
		    call LagrangianRemesh(sphere,refSphere,vortRefine,tracerRefine,flowMapRefine)
		    call SetFlowMapLatitudeTracerOnMesh(sphere,3)
		endif
		!
		!	create new associated objects
		!
		call New(bveRK4,sphere,numProcs)
		call New(vtkOut,sphere,vtkFile,'gaussVort')

		write(logString,'(A,I4)') 'remesh ', remeshCounter
		if ( procRank == 0 ) call LogStats(sphere,exelog,trim(logString))
	endif
	!
	!	advance timestep
	!
	call BVERK4Timestep(bveRK4, sphere, dt, procRank, numProcs)

	if ( timeJ == 0 ) totalKE(0) = sphere%totalE
	totalKE(timeJ+1) = sphere%totalE
	totalEns(timeJ+1) = TotalEnstrophy(sphere)
	massIntegral(timeJ+1) = TotalMass(sphere,1)

	t = real(timeJ+1,kreal)*dt
	!
	!	output timestep data
	!
	if ( procRank == 0 .AND. mod(timeJ+1,frameOUt) == 0  ) then
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,'day = ',t/ONE_DAY)
		write(vtkFile,'(A,I0.4,A)') trim(vtkRoot), frameCounter, '.vtk'
		call UpdateFileName(vtkOut,vtkFile)
		call VTKOutput(vtkOut,sphere)
		frameCounter = frameCounter + 1
	endif
enddo
!
!	output final data
!
if ( procRank == 0 ) then
	write(vtkRoot,'(A,A,A,A,A)') trim(outputDir), '/vtkOut/',trim(jobPrefix),trim(amrString),'_'
	write(conservedDataFile,'(6A)') trim(outputDir), '/',trim(jobPrefix), trim(amrString),'_conservedData', '.txt'
	write(summaryFile,'(6A)') trim(outputDir), '/',trim(jobPrefix), trim(amrString),'_summary', '.txt'

	open(unit=WRITE_UNIT_1,file=conservedDataFile,status='REPLACE',action='WRITE',iostat=writeStat1)
	if ( writeStat1 /= 0 ) then
		call LogMessage(exeLog,ERROR_LOGGING_LEVEL,trim(logKey),' ERROR writing final data.')
	else
		write(WRITE_UNIT_1,'(3A24)') 'totalMass', 'totalKE', 'totalEns'
		do j = 0, timesteps
			write(WRITE_UNIT_1,'(E24.8,E24.8, E24.8)') massIntegral(j), totalKE(j), totalEns(j)
		enddo
	endif
	close(WRITE_UNIT_1)

	call New(writer,WRITE_UNIT_2,summaryFile)
	call StartSection(writer,'JOB SUMMARY :',' SINGLE GAUSSIAN VORTEX')
	call Write(writer,'tfinal = ',tfinal)
	call Write(writer,'dt = ', dt )
	call Write(writer,'remeshInterval = ',remeshInterval)
	call Write(writer,'resetAlpha = ', resetAlpha)
	if (AMR > 0 ) then
		call Write(writer,'AMR, initNest = ', initNest)
		call Write(writer,'AMR, maxNest = ', maxval(sphere%panels%nest))
		call Write(writer,'AMR, refinementLimit = ', refinementLimit)
		call Write(writer,'circMaxTol = ', vortRefine%maxTol)
		call Write(writer,'relVortVarTol = ', vortRefine%varTol)
		call Write(writer,'tracer1 maxTol = ', tracerRefine%maxTol)
		call Write(writer,'tracer1 varTol = ', tracerRefine%maxTol)
		call Write(writer,'flowMap varTol = ', flowMapRefine%varTol)
	else
		call Write(writer,'uniformMesh, initNest = ', initNest)
	endif

	call Delete(writer)
endif
! TO DO : output final data



!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	Clear memory and Finalize
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

write(logstring,'(A, F8.2,A)') 'elapsed time = ', (MPI_WTIME() - wallClock)/60.0, ' minutes.'
call LogMessage(exelog,TRACE_LOGGING_LEVEL,'PROGRAM COMPLETE : ',trim(logstring))

deallocate(totalKE)
deallocate(totalEns)
deallocate(massIntegral)
if ( refSphereReady ) call Delete(refSphere)
call Delete(bveRK4)
if ( procRank == 0 ) call Delete(vtkOut)
call Delete(vortRefine)
call Delete(tracerRefine)
call Delete(flowmapRefine)
call Delete(cosBell)
call Delete(gaussVort)
call Delete(exeLog)
call MPI_FINALIZE(mpiErrCode)

contains

subroutine ReadNamelistfile(rank)
	integer(kint), intent(in) :: rank
	if ( rank == 0 ) then
		open(unit = READ_UNIT, file = namelistInputFile, status = 'OLD', action = 'READ',iostat= readStat)
			if ( readstat /= 0 ) then
				stop 'cannot read namelist file.'
			endif
			read(READ_UNIT,nml=sphereDefine)
			rewind(READ_UNIT)
            read(READ_UNIT,nml=vorticityDefine)
            rewind(READ_UNIT)
			read(READ_UNIT,nml=timestepping)
			rewind(READ_UNIT)
			read(READ_UNIT,nml=fileIO)

			broadcastIntegers(1) = panelKind
			broadcastIntegers(2) = AMR
			broadcastIntegers(3) = initNest
			broadcastIntegers(4) = refinementLimit
			broadcastIntegers(5) = remeshInterval
                        broadcastIntegers(6) = resetAlpha

			broadcastReals(1) = tracerMaxTol
			broadcastReals(2) = tracerVarTol
			broadcastReals(3) = tfinal
			broadcastReals(4) = circMaxTol
			broadcastReals(5) = vortVarTol
			broadcastReals(6) = dt
			broadcastReals(7) = lagVarTol
			broadcastReals(8) = vortLat
			broadcastReals(9) = vortLon
			broadcastReals(10) = bb
			broadcastReals(11) = maxVort
	endif
end subroutine

subroutine InitLogger(alog,rank)
	type(Logger), intent(out) :: aLog
	integer(kint), intent(in) :: rank
	if ( rank == 0 ) then
		call New(aLog,DEBUG_LOGGING_LEVEL)
	else
		call New(aLog,DEBUG_LOGGING_LEVEL)
	endif
        write(logKey,'(A,I0.2,A)') 'EXE_LOG',procRank,' : '
end subroutine

end program
