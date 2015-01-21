program RH4Wave
!******************************************************************************
!	Peter A. Bosler
!	Department of Mathematics
!	University of Michigan
!	pbosler@umich.edu
!
!******************************************************************************
!
!	This program solves the barotropic vorticity equation for the case of a Rossby-Haurwitz wave on the sphere.
!
!	Bosler, P.A., "Particle Methods for Geophysical Flow on the Sphere," PhD Thesis; the University of Michigan, 2013.
!
!	Haurwitz, B. "The motion of atmospheric disturbances on the spherical Earth," Journal of Marine Research, 1940.
!
!----------------
use NumberKindsModule
use SphereGeomModule
use OutputWriterModule
use LoggerModule
use ParticlesModule
use PanelsModule
use SphereMeshModule
!use RefineRemeshModule
use TracerSetupModule
use VTKOutputModule
use BVESetupModule
use BVEDirectSumModule
!use ReferenceSphereModule
use SphereRemeshModule
use LatLonOutputModule

implicit none

include 'mpif.h'

!
!	mesh variables
!
type(SphereMesh) :: sphere
integer(kint) :: panelKind, initNest, AMR, nTracer, problemKind
type(Particles), pointer :: sphereParticles => null()
type(Panels), pointer :: spherePanels => null()
!
!	time stepping variables
!
type(BVERK4Data) :: bveRK4
real(kreal) :: t, dt, tfinal
integer(kint) :: timesteps, timeJ
!
!	vorticity variables
!
type(BVESetup) :: rhWave
real(kreal) :: alpha, amp, beta
real(kreal), allocatable :: totalE(:), totalEns(:), vortErrorLinf(:), vortErrorL2(:)
real(kreal), allocatable :: exactVortParticles(:), exactVortPanels(:)
!
!	tracer variables
!
type(tracerSetup) :: nullScalar
!
!	refinement / remeshing variables
!
type(RemeshSetup) :: remesh
type(ReferenceSphere) :: reference
real(kreal) :: maxCircTol, vortVarTol, lagVarTol
integer(kint) :: amrLimit, remeshInterval, remeshCounter, resetAlpha

!
!	Output variables
!
type(VTKSource) :: vtkOut
type(LLSource) :: LLOut
character(len = 128) :: vtkRoot, vtkFile, outputDir, jobPrefix, LLRoot, LLFile
character(len = 128) :: dataFile, summaryFile
character(len = 56 ) :: amrString
integer(kint) :: frameCounter, frameOut, writeStat1, writeStat2
type(OutputWriter) :: writer
integer(kint) :: nLon, outputContours
!
!	User input
!
character(len = 128) :: namelistInputFile = 'RH4Wave.namelist'
integer(kint) :: readStat
namelist /sphereDefine/ panelKind, initNest, AMR, amrLimit, maxCircTol, vortVarTol, lagVarTol
namelist /vorticityDefine/ 	alpha, amp
namelist /timeStepping/ tfinal, dt,  remeshInterval, resetAlpha
namelist /fileIO/ outputDir, jobPrefix, frameOut, nLon, outputContours
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
integer(kint), parameter  :: BROADCAST_INT_SIZE = 6, BROADCAST_REAL_SIZE = 7
integer(kint) :: broadcastIntegers(BROADCAST_INT_SIZE)
real(kreal) :: broadcastReals(BROADCAST_REAL_SIZE)
real(kreal) :: wallClock

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	PROGRAM START
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
call MPI_INIT(mpiErrCode)
call MPI_COMM_SIZE(MPI_COMM_WORLD,numProcs,mpiErrCode)
call MPI_COMM_RANK(MPI_COMM_WORLD,procRank,mpiErrCode)

call InitLogger(exeLog,procRank)


wallClock = MPI_WTIME()
!
!	read user input from namelist file, set starting state
!
call ReadNamelistFile(procRank)
nTracer = 3
problemKind = BVE_SOLVER

call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logKey),' initial broadcasts done.')

!
!	define test case
!
call New(rhWave,RH4_NINT, RH4_NREAL)
call InitRH4Wave(rhWave,alpha,amp)
call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logKey),' vorticity object done.')

call New(nullScalar, 0, 0)
call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logKey),' null tracer object done.')

!
!	initialize sphere
!
call New(sphere,panelKind,initNest,AMR,nTracer,problemKind)
call SetFlowMapLatitudeTracerOnMesh(sphere,1)
call SetFlowMapLatitudeTracerOnMesh(sphere,2)
call SetRH4WaveOnMesh(sphere,rhWave, 0.0_kreal)
call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logKey),' base sphere (t = 0) done.')

!
! 	initialize remeshing
!
call ConvertToRelativeTolerances(sphere, maxCircTol, vortVarTol, lagVarTol)
call LogMessage(exeLog, TRACE_LOGGING_LEVEL, 'maxCircTol = ', maxCircTol)
call LogMessage(exeLog, TRACE_LOGGING_LEVEL, 'vortVarTol = ', vortVarTol)
call LogMessage(exeLog, TRACE_LOGGING_LEVEL, 'lagVarTol  = ', lagVarTol)

call New(remesh, maxCircTol, vortVarTol, lagVarTol, amrLimit)



if ( AMR > 0 ) then
	call InitialRefinement(sphere, remesh, nullTracer, nullScalar, SetRH4WaveOnMesh, rhWave, 0.0_kreal)
	call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,' initial refinement done.')

	if ( panelKind == QUAD_PANEL) then
		write(amrString,'(A,I1,A,I0.2,A)') 'quadAMR_',initNest,'to',initNest+amrLimit,'_'
	endif
else
	! uniform mesh
	if ( panelKind == QUAD_PANEL ) then
		write(amrString,'(A,I1,A)') 'quadUnif',initNest,'_'
	endif
endif
call SetFlowMapLatitudeTracerOnMesh(sphere,1)
call SetFlowMapLatitudeTracerOnMesh(sphere,2)
!
!	initialize output, output t = 0 data
!
frameCounter = 0
if ( procRank == 0 ) then
	call LogStats(sphere,exeLog,'initial mesh :')
	write(vtkRoot,'(A,A,A,A,A)') trim(outputDir), '/vtkOut/',trim(jobPrefix),trim(amrString),'_'
	write(vtkFile,'(A,I0.4,A)') trim(vtkRoot),frameCounter,'.vtk'


	call New(vtkOut,sphere,vtkFile,'RH4Wave')
	!call VTKOutputMidpointRule(vtkOut,sphere)
	call VTKOutput(vtkOut,sphere)

	if ( outputContours > 0 ) then
		write(LLRoot,'(A,A,A,A,A)') trim(outputDir), '/LLOut/',trim(jobPrefix),trim(amrString),'_'
		write(LLFile,'(A,I0.4,A)') trim(LLRoot),frameCounter,'.m'

		call New(LLOut,sphere,LLFile,nLon)
		call LLOutputMatlab(LLOut,sphere)
	endif

	frameCounter = frameCounter + 1
endif
!
!	intialize timestepping
!
call New(bveRK4,sphere,numProcs)
timesteps = floor(tfinal/dt)
t = 0.0_kreal
remeshCounter = 0
allocate(totalE(0:timesteps))
allocate(totalEns(0:timesteps))
allocate(vortErrorLinf(0:timesteps))
allocate(vortErrorL2(0:timesteps))
totalE = 0.0_kreal
totalEns = 0.0_kreal
vortErrorLinf = 0.0_kreal
vortErrorL2 = 0.0_kreal
totalEns(0) = TotalEnstrophy(sphere)

sphereParticles => sphere%particles
spherePanels => sphere%panels
allocate(exactVortParticles(sphereparticles%N_Max))
allocate(exactVortPanels(spherepanels%N_Max))
exactVortParticles = 0.0_kreal
exactVortPanels = 0.0_kreal
beta = 2.0_kreal*(OMEGA - alpha)*4.0_kreal/30.0_kreal - alpha*4.0_kreal
do j=1, sphereParticles%N
	exactVortParticles(j) = RH54Vorticity(sphereParticles%x(:,j), alpha, amp)
enddo
do j=1, spherePanels%N
	if ( .NOT. spherePanels%hasChildren(j) ) exactVortPanels(j) = RH54Vorticity(spherePanels%x(:,j), alpha, amp)
enddo

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
		!
		! remesh before time step
		!
		remeshCounter = remeshCounter + 1
		!
		! choose appropriate remeshing procedure
		!
		if ( remeshCounter < resetAlpha ) then
			!
			! remesh to t = 0
			!
			call LagrangianRemeshToInitialTime(sphere, remesh, SetRH4WaveOnMesh, rhWave, nulltracer, nullscalar)
			call SetFlowMapLatitudeTracerOnMesh(sphere,1)
			call SetFlowMapLatitudeTracerOnMesh(sphere,2)
		elseif ( remeshCounter == resetAlpha ) then
			!
			! remesh to t = 0, create reference to current time
			!
			call LagrangianRemeshToInitialTime(sphere, remesh, SetRH4WaveOnMesh, rhWave, nulltracer, nullscalar)
			call SetFlowMapLatitudeTracerOnMesh(sphere,1)
			call SetFlowMapLatitudeTracerOnMesh(sphere,2)
			call New(reference, sphere)
			call ResetLagrangianParameter(sphere)
		elseif ( remeshCounter > resetAlpha .AND. mod(remeshCounter, resetAlpha) == 0 ) then
			!
			! remesh to previous reference time, create new reference to current time
			!
			call LagrangianRemeshToReference(sphere, reference, remesh)
			call Delete(reference)
			call New(reference, sphere)
			call SetFlowMapLatitudeTracerOnMesh(sphere,2)
			call ResetLagrangianParameter(sphere)
		else
			!
			! remesh to reference
			!
			call LagrangianRemeshToReference(sphere, reference, remesh)
		endif
		
		!
		! delete objects associated with old mesh
		!
		call Delete(bveRK4)
		if ( procRank == 0 ) call Delete(vtkOut)
		
		!
		! create new associated objects for new mesh
		!
		call New(bveRK4, sphere, numProcs)
		if ( procRank == 0 ) call New(vtkOut,sphere,vtkFile,'RH4Wave')
	endif
	!
	!	advance timestep
	!
	call BVERK4Timestep(bveRK4, sphere, dt, procRank, numProcs)
	!
	!	error calculations
	!
	if ( timeJ == 0 ) totalE(0) = sphere%totalE
	totalE(timeJ+1) = sphere%totalE
	totalEns(timeJ+1) = TotalEnstrophy(sphere)

	t = real(timeJ+1,kreal)*dt

	do j=1,sphereParticles%N
		exactVortParticles(j) = -30.0_kreal*amp*cos(beta*t + 4.0_kreal*Longitude(sphereParticles%x(:,j)))*&
				Legendre54(sphereParticles%x(3,j)/EARTH_RADIUS)/EARTH_RADIUS - 2.0_kreal*alpha*sphereParticles%x(3,j)/EARTH_RADIUS
		sphereParticles%tracer(j,3) = abs(exactVortParticles(j) - sphereParticles%relVort(j))
	enddo
	do j=1,spherePanels%N
		if ( .NOT. spherePanels%hasChildren(j) ) then
			exactVortPanels(j) = -30.0_kreal*amp*cos(beta*t + 4.0_kreal*Longitude(spherePanels%x(:,j)))*&
				Legendre54(spherePanels%x(3,j)/EARTH_RADIUS)/EARTH_RADIUS - 2.0_kreal*alpha*spherePanels%x(3,j)/EARTH_RADIUS
			spherePanels%tracer(j,3) = abs(exactVortPanels(j) - spherePanels%relVort(j))
		endif
	enddo

	vortErrorLinf(timeJ+1) = maxval(spherePanels%tracer(1:spherePanels%N,3))/maxVal(abs(spherePanels%relVort(1:spherePanels%N)))
	vortErrorL2(timeJ+1) = sqrt(sum(spherePanels%tracer(1:spherePanels%N,3)*spherePanels%tracer(1:spherePanels%N,3)*&
		spherePanels%area(1:spherePanels%N))) / &
		sqrt(sum(spherePanels%relVort(1:spherePanels%N)*spherePanels%relVort(1:spherePanels%N)*spherePanels%area(1:spherePanels%N)))
	!
	!	output timestep data
	!
	if ( procRank == 0 .AND. mod(timeJ+1,frameOUt) == 0  ) then
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,'day = ',t/ONE_DAY)

		write(vtkFile,'(A,I0.4,A)') trim(vtkRoot), frameCounter, '.vtk'
		call UpdateFileName(vtkOut,vtkFile)
		!call VTKOutputMidpointRule(vtkOut,sphere)
		call VTKOutput(vtkOut,sphere)

		if ( outputContours > 0 ) then
			write(LLFile,'(A,I0.4,A)') trim(LLRoot), frameCounter, '.m'
			call UpdateFileName(LLOut,LLFile)
			call LLOutputMatlab(LLOut,sphere)
		endif
		frameCounter = frameCounter + 1
	endif
enddo
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	Output final data
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if ( procRank == 0 ) then


	write(dataFile,'(6A)') trim(outputDir),'/', trim(jobPrefix), trim(amrString),'_finalData','.txt'
	write(summaryFile,'(6A)') trim(outputDir),'/', trim(jobPrefix), trim(amrString),'_summary','.txt'

	open(unit=WRITE_UNIT_1,file = dataFile, status='REPLACE', action='WRITE',iostat=writeStat1)
	if ( writeStat1 /= 0 ) then
		call LogMessage(exeLog,ERROR_LOGGING_LEVEL,trim(logKey),' ERROR writing final data.')
	else
		write(WRITE_UNIT_1,'(4A24)') 'totalE', 'totalEns', 'vortL2', 'vortLinf'
		write(WRITE_UNIT_1,'(A)') 'finalData = ['
		do j=0, timesteps
			write(WRITE_UNIT_1,'(4E24.8, A)') totalE(j), totalEns(j), vortErrorL2(j), vortErrorLinf(j), ' ; ...'
		enddo
		write(WRITE_UNIT_1,'(A)') '];'
	endif
	close(WRITE_UNIT_1)

	call New(writer,WRITE_UNIT_2,summaryFile)
	call StartSection(writer,'JOB SUMMARY : ',' ROSSBY-HAURWITZ 54 WAVE ')
	call Write(writer,'RH wave alpha = ',alpha)
	call Write(writer,'RH wave amplitude = ', amp)
	call Write(writer,'tfinal (days) = ',tfinal/ONE_DAY)
	call Write(writer,'dt (seconds) = ', dt)
	call Write(writer,'remeshInterval = ',remeshInterval)
	call Write(writer,'reset LagParam = ',resetAlpha)
	if (AMR > 0 ) then
		call Write(writer,'AMR initNest = ', initNest)
		call Write(writer,'AMR maxNest = ', maxval(sphere%panels%nest)) 
		call Write(writer,'AMR amrLimit = ', amrLimit )
		call Write(writer,'AMR maxCircTol = ', maxCircTol )
		call Write(writer,'AMR relVortVarTol = ', vortVarTol )
		call Write(writer,'AMR flowMap varTol = ', lagVarTol )
	else
		call Write(writer,'uniformMesh, initNest = ', initNest)
	endif
	call Delete(writer)
endif

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!	Clear memory and Finalize
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if ( procRank == 0 ) then
	write(logstring,'(A, F8.2,A)') 'elapsed time = ', (MPI_WTIME() - wallClock)/60.0, ' minutes.'
	call LogMessage(exelog,TRACE_LOGGING_LEVEL,'PROGRAM COMPLETE : ',trim(logstring))
	call Delete(vtkOut)
	if (outputContours > 0 ) call Delete(LLOut)
endif
call Delete(bveRK4)
deallocate(totalE)
deallocate(totalEns)
deallocate(vortErrorLinf)
deallocate(vortErrorL2)
call Delete(sphere)
call Delete(remesh)
call Delete(rhWave)
call Delete(nullScalar)
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
			broadcastIntegers(4) = amrLimit
			broadcastIntegers(5) = remeshInterval
            broadcastIntegers(6) = resetAlpha

			broadcastReals(1) = alpha
			broadcastReals(2) = amp
			broadcastReals(3) = tfinal
			broadcastReals(4) = maxCircTol
			broadcastReals(5) = vortVarTol
			broadcastReals(6) = dt
			broadcastReals(7) = lagVarTol
		close(READ_UNIT)	
	endif
	call MPI_BCAST(broadcastIntegers,BROADCAST_INT_SIZE,MPI_INTEGER,0,MPI_COMM_WORLD,mpiErrCode)
	panelKind = broadcastIntegers(1)
	AMR = broadcastIntegers(2)
	initNest = broadcastIntegers(3)
	amrLimit = broadcastIntegers(4)
	remeshInterval = broadcastIntegers(5)
	resetAlpha = broadcastIntegers(6)

	call MPI_BCAST(broadcastReals,BROADCAST_REAL_SIZE,MPI_DOUBLE_PRECISION,0,MPI_COMM_WORLD,mpiErrCode)
	alpha = broadcastReals(1)
	amp = broadcastReals(2)
	tfinal = broadcastReals(3)*ONE_DAY ! convert tfinal to seconds
	maxCircTol = broadcastReals(4)
	vortVarTol = broadcastReals(5)
	dt = broadcastReals(6) * ONE_DAY ! convert dt to seconds
	lagVarTol = broadcastReals(7)
end subroutine


subroutine ConvertToRelativeTolerances(aMesh, maxCircTol, vortVarTol, lagVarTol)
	type(SphereMesh), intent(in) :: aMesh
	real(kreal), intent(inout) :: maxCircTol, vortVarTol, lagVarTol
	maxCircTol = maxCircTol * MaximumCirculation(aMesh)
	vortVarTol = vortVarTol * MaximumVorticityVariation(aMesh)
	lagVarTol = lagVarTol * AverageLagrangianParameterVariation(aMesh)
end subroutine

subroutine InitLogger(alog,rank)
	type(Logger), intent(out) :: aLog
	integer(kint), intent(in) :: rank
	if ( rank == 0 ) then
		call New(aLog,DEBUG_LOGGING_LEVEL)
	else
		call New(aLog,WARNING_LOGGING_LEVEL)
	endif
        write(logKey,'(A,I0.2,A)') 'EXE_LOG',rank,' : '
end subroutine


end program
