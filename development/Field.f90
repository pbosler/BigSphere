module FieldModule

use NumberKindsModule
use LoggerModule
use ParticlesModule
use FacesModule

implicit none
private
public Field
public New, Delete
public InsertScalarToField, InsertVectorToField
public WriteFieldToVTKPointData, WriteFieldToVTKCellData
public WriteFieldToMatlab
public LogStats
!public SetFieldToScalarFunction, SetFieldToVectorFunction

type Field
	real(kreal), pointer :: scalar(:) => null()
	real(kreal), pointer :: xComp(:) => null()
	real(kreal), pointer :: yComp(:) => null()
	real(kreal), pointer :: zComp(:) => null()
	character(MAX_STRING_LENGTH) :: name = "null"
	character(MAX_STRING_LENGTH) :: units = "null"
	integer(kint) :: N = 0
	integer(kint) :: N_Max = 0
	integer(kint) :: nDim = 0
end type	

interface New
	module procedure NewPrivate
end interface

interface Delete
	module procedure DeletePrivate
end interface

interface LogStats
	module procedure LogStatsPrivate
end interface

!interface ScalarFieldFunction
!	function ScalarFunctionOfSpace( xVec )
!		real(8) :: ScalarFunctionOfSpace
!		real(8), intent(in) :: xVec(:)
!	end function
!	
!	function ScalarFunctionOfSpaceAndTime( xVec, t)
!		real(8) :: ScalarFunctionOfSpaceAndTime
!		real(8), intent(in) :: xVec(:)
!		real(8), intent(in) :: t
!	end function 
!end interface
!
!interface VectorFieldFunction
!	function VectorFunctionOfSpace( xVec )
!		real(8) :: VectorFunctionOfSpace
!		real(8), intent(in) :: xVec(:)
!	end function 
!	
!	function VectorFunctionOfSpaceAndTime( xVec, t )
!		real(8) :: VectorFunctionOfSpaceAndTime
!		real(8), intent(in) :: xVec(:)
!		real(8), intent(in) :: t
!	end function
!end interface

!
!----------------
! Logging
!----------------
!
logical(klog), save :: logInit = .FALSE.
type(Logger) :: log
character(len=28), save :: logKey = 'FieldLog'
integer(kint), parameter :: logLevel = DEBUG_LOGGING_LEVEL

contains

subroutine NewPrivate(self, nDim, nMax, name, units )
	type(Field), intent(out) :: self
	integer(kint), intent(in) :: nDim, nMax
	character(len=*), intent(in), optional :: name, units
	
	if ( .NOT. logInit ) call InitLogger(log, procRank)
	
	if ( nDim <= 0 ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL, logkey, " invalid nMax.")
		return
	endif
	
	self%N_Max = nMax
	self%nDim = nDim
	self%N = 0
	select case (nDim)
		case (1)
			allocate(self%scalar(nMax))
			self%scalar = 0.0
		case (2)
			allocate(self%xComp(nMax))
			allocate(self%yComp(nMax))
			self%xComp = 0.0
			self%yComp = 0.0
		case (3)
			allocate(self%xComp(nMax))
			allocate(self%yComp(nMax))
			allocate(self%zComp(nMax))
			self%xComp = 0.0
			self%yComp = 0.0
			self%zComp = 0.0
		case default
	end select 
	
	if ( present(name) ) then
		self%name = trim(name)
	endif
	
	if ( present(units) ) then
		self%units = trim(units)
	endif
end subroutine

subroutine DeletePrivate(self)
	type(Field), intent(inout) :: self
	if ( associated(self%scalar) ) deallocate(self%scalar)
	if ( associated(self%xComp) ) deallocate(self%xComp)
	if ( associated(self%yComp) ) deallocate(self%yComp)
	if ( associated(self%zComp) ) deallocate(self%zComp)
end subroutine

subroutine InsertScalarToField(self, val)
	type(Field), intent(inout) :: self
	real(kreal), intent(in) :: val
	if ( .NOT. associated(self%scalar) ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL,logkey," InsertScalarToField : scalar not allocated.")
		return
	endif
	if ( self%N >= self%N_Max ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL, logKey, " InsertScalarToField : out of memory.")
		return
	endif
	self%scalar( self%N + 1 ) = val
	self%N = self%N + 1
end subroutine

subroutine InsertVectorToField( self, vecVal )
	type(Field), intent(inout) :: self
	real(kreal), intent(in) :: vecVal(:)
	
	if ( self%N >= self%N_Max ) then
		call LogMessage(log, ERROR_LOGGING_LEVEL, logKey, " InsertVectorToField : out of memory.")
		return
	endif
	if ( self%nDim == 2 .AND. size(vecVal) == 2 ) then
		self%xComp( self%N + 1 ) = vecVal(1)
		self%yComp( self%N + 1 ) = vecVal(2)
	elseif ( self%nDim == 3 .AND. size(vecVal) == 3 ) then
		self%xComp( self%N + 1 ) = vecVal(1)
		self%yComp( self%N + 1 ) = vecVal(2)
		self%yComp( self%N + 1 ) = vecVal(3)
	else
		call LogMessage(log, ERROR_LOGGING_LEVEL, logKey, " InsertVectorToField : size mismatch.")
		return
	endif
	self%N = self%N + 1
end subroutine

subroutine InitLogger(aLog,rank)
! Initialize a logger for this module and processor
	type(Logger), intent(out) :: aLog
	integer(kint), intent(in) :: rank
	write(logKey,'(A,A,I0.3,A)') trim(logKey),'_',rank,' : '
	call New(aLog,logLevel)
	logInit = .TRUE.
end subroutine

subroutine WriteFieldToVTKPointData( self, fileunit )
	type(Field), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	!
	integer(kint) :: j
	
	write(fileunit,'(A,I8)') "POINT_DATA ", self%N
	write(fileunit,'(5A,I4)') "SCALARS ", trim(self%name), "_", trim(self%units) , "double ", self%nDim
	write(fileunit,'(A)') "LOOKUP_TABLE default"
	
	select case (self%nDim)
		case (1)
			do j = 1, self%N
				write(fileunit,*) self%scalar(j)
			enddo
		case (2)
			do j = 1, self%N
				write(fileunit,*) self%xComp(j), self%yComp(j)
			enddo
		case (3)
			do j = 1, self%N
				write(fileunit,*) self%xComp(j), self%yComp(j), self%zComp(j)
			enddo
	end select
end subroutine

subroutine WriteFieldToVTKCellData( self, fileunit, aFaces )
	type(Field), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	type(Faces), intent(in) :: aFaces
	!
	integer(kint) :: i, j, nCells, nVerts
	
	nVerts = size(aFaces%vertices, 1)
	nCells = nVerts * aFaces%N_Active
	
	write(fileunit,'(A,I8)') "CELL_DATA ", nCells
	write(fileunit,'(5A,I4)') "SCALARS ", trim(self%name), "_", trim(self%units) , "double ", self%nDim
	write(fileunit,'(A)') "LOOKUP_TABLE default"
	
	select case ( self%nDim )
		case (1)
			do i = 1, aFaces%N
				if ( .NOT. aFaces%hasChildren(i) ) then
					do j = 1, nVerts
						write(fileunit,*) self%scalar( aFaces%centerParticle(i) )
					enddo
				endif
			enddo 
		case (2)
			do i = 1, aFaces%N
				if ( .NOT. aFaces%hasChildren(i) ) then
					do j = 1, nVerts
						write(fileunit, *) self%xComp( aFaces%centerParticle(i)), self%yComp( aFaces%centerParticle(j))
					enddo
				endif
			enddo
		case (3)
			do i = 1, aFaces%N
				if ( .NOT. aFaces%hasChildren(i) ) then
					do j = 1, nVerts
						write(fileunit, *) self%xComp( aFaces%centerParticle(j)), self%yComp( aFaces%centerParticle(j)),&
									   self%zComp(aFaces%centerParticle(j))
					enddo
				endif
			enddo
	end select
end subroutine

subroutine LogStatsPrivate(self, aLog )
	type(Field), intent(in) :: self
	type(Logger), intent(inout) :: aLog 
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, logkey, "FieldStats:"//trim(self%name) )
	call StartSection(aLog)
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "Field.nDim = ", self%nDim)
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "Field.N = ", self%N)
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "Field.name = ", self%name)
	call LogMessage(aLog, TRACE_LOGGING_LEVEL, "Field.units = ", self%units)
	if (self%nDim == 1 ) then
		 call LogMessage(alog, TRACE_LOGGING_LEVEL,"max scalar = ", maxval(self%scalar(1:self%N)))
		 call LogMessage(alog, TRACE_LOGGING_LEVEL,"min scalar = ", minval(self%scalar(1:self%N)))
	else
		call LogMessage(alog, TRACE_LOGGING_LEVEL, "max magnitude = ", MaxMagnitude(self) ) 
		call LogMessage(aLog, TRACE_LOGGING_LEVEL, "min magnitude = ", MinMagnitude(self) )
	endif
	call EndSection(aLog)
end subroutine

function MaxMagnitude(self)
	real(kreal) :: MaxMagnitude 
	type(Field), intent(in) :: self
	!
	integer(kint) :: i
	real(kreal) :: mag
	MaxMagnitude = -1.0d64
	if (self%nDim == 2 ) then
		do i = 1, self%N
			mag = sqrt( self%xComp(i)*self%xComp(i) + self%yComp(i)*self%yComp(i))
			if ( mag > MaxMagnitude ) MaxMagnitude = mag
		enddo
	else if ( self%nDim == 3 ) then
		do i = 1, self%N
			mag = sqrt( self%xComp(i)*self%xComp(i) + self%yComp(i)*self%yComp(i) + self%zComp(i)*self%zComp(i))
			if ( mag > MaxMagnitude ) MaxMagnitude = mag
		enddo 	
	endif
end function 

function MinMagnitude(self)
	real(kreal) :: MinMagnitude 
	type(Field), intent(in) :: self
	!
	integer(kint) :: i
	real(kreal) :: mag
	MinMagnitude = 1.0d64
	if (self%nDim == 2 ) then
		do i = 1, self%N
			mag = sqrt( self%xComp(i)*self%xComp(i) + self%yComp(i)*self%yComp(i))
			if ( mag < MinMagnitude ) MinMagnitude = mag
		enddo
	else if ( self%nDim == 3 ) then
		do i = 1, self%N
			mag = sqrt( self%xComp(i)*self%xComp(i) + self%yComp(i)*self%yComp(i) + self%zComp(i)*self%zComp(i))
			if ( mag < MinMagnitude ) MinMagnitude = mag
		enddo 	
	endif
end function

subroutine WriteFieldToMatlab( self, fileunit )
	type(Field), intent(in) :: self
	integer(kint), intent(in) :: fileunit
	!
	integer(kint) :: i
	
	select case ( self%nDim )
		case (1)
			write(fileunit,*) "scalarField_", trim(self%name), " = [", self%scalar(1), ", ..."
			do i = 2, self%N - 1
				write(fileunit, *) self%scalar(i), ", ..."
			enddo
			write(fileunit, *) self%scalar(self%N), "];"
		case (2)
			write(fileunit,*) "vectorField_", trim(self%name), " = [", self%xComp(1), ", ", self%yComp(1), "; ..."
			do i = 2, self%N - 1
				write(fileunit,*) self%xComp(i), ", ", self%yComp(i), "; ..."
			enddo
			write(fileunit,*) self%xComp(self%N), ", ", self%yComp(self%N), "];"
		case (3)
			write(fileunit,*) "vectorField_", trim(self%name), " = [", self%xComp(1), ", ",&
										 self%yComp(1), ", ", self%zComp(1), "; ..."
			do i = 2, self%N
				write(fileunit,*) self%xComp(i), ", ", self%yComp(i), ", ", self%zComp(i), "; ..."
			enddo							 
			write(fileunit,*) self%xComp(self%N), ", ", self%yComp(self%N), ", ", self%zComp(self%N), "];"
	end select	
end subroutine

end module