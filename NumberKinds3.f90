module NumberKindsModule
!------------------------------------------------------------------------------
! Lagrangian Particle / Panel Method - Spherical Model
!------------------------------------------------------------------------------
!
!> @author
!> Peter Bosler, Department of Mathematics, University of Michigan
!
!> @defgroup NumberKinds Number kinds module
!> Defines global numerical constants for use by all LPPM modules and executables.
!> 
!
!
! DESCRIPTION:
!> @file
!> Defines global numerical constants for use by all LPPM modules and executables.
!
!------------------------------------------------------------------------------
	implicit none
	public

	!> @defgroup TypeConstants Type Constants 
	!> @brief sets compiler-dependent kind variables for primitive data types
	integer, parameter :: KREAL = kind(0.d0)   !<< compiler generated kind for double precision reals @ingroup TypeConstants
	integer, parameter :: KINT = kind(1)	   !<< compiler generated kind for default integer @ingroup TypeConstants
	integer, parameter :: KLOG = kind(.TRUE.)  !<< compiler generated kind logical @ingroup TypeConstants

	real(KREAL), parameter :: ZERO_TOL = 1.0d-10 !<< zero tolerance for real numbers @ingroup TypeConstants

	!> @defgroup PhysicalConstants Physical Constants
	!> @brief Physical constants referenced from @cite CAM3.0
	real(KREAL), parameter :: PI = 3.1415926535897932384626433832795027975_KREAL !<< Pi @ingroup PhysicalConstants
	real(KREAL), parameter :: RAD_2_DEG = 180.0_kreal/PI !<<  convert radians to degrees @ingroup PhysicalConstants
	real(KREAL), parameter :: GRAV = 9.80616 !<< acceleration due to gravity {m s^(-2)} @ingroup PhysicalConstants
	real(KREAL), parameter :: ONE_DAY = 86140.0_kreal !<< Earth's sidereal day {s} @ingroup PhysicalConstants
	real(KREAL), parameter :: EARTH_RADIUS = 6371220_kreal !<< mean radius of the Earth { m } @ingroup PhysicalConstants
    real(KREAL), save ::	  OMEGA = 2.0_kreal*PI / ONE_DAY  !<< rotation rate of sphere {s^(-1)} @ingroup PhysicalConstants
    real(KREAL), parameter :: EARTH_SURFACE_AREA = 4.0_kreal * PI * EARTH_RADIUS * EARTH_RADIUS


	!> @defgroup IOConstants I/O Constants
	!> @brief constants for file input and output
	integer(KINT), parameter :: STD_ERR = 0
	integer(KINT), parameter :: STD_IN  = 5
	integer(KINT), parameter :: STD_OUT = 6
	integer(KINT), parameter :: READ_UNIT = 11
	integer(KINT), parameter :: WRITE_UNIT_1 = 12
	integer(KINT), parameter :: WRITE_UNIT_2 = 13
	integer(KINT), parameter :: WRITE_UNIT_3 = 14
	integer(KINT), parameter :: MAX_STRING_LENGTH = 256
	
	!> @defgroup MeshConstants Mesh and application constants
	!> @brief constants for mesh and problem definition
	integer(KINT), parameter ::	QUAD_PANEL = 4 !<< panelKind parameter for quadrilateral panels @ingroup MeshConstants
	integer(KINT), parameter ::	TRI_PANEL = 3 !<< panelKind parameter for triangular panels @ingroup MeshConstants
	integer(KINT), parameter ::	ADVECTION_SOLVER = 90 !<< problemKind parameter for spherical advection @ingroup MeshConstants
	integer(KINT), parameter ::	BVE_SOLVER = 91 !<< problemKind parameter for quadrilateral panels @ingroup MeshConstants
	integer(KINT), parameter ::	SWE_SOLVER = 92	!<< problemKind parameter for quadrilateral panels @ingroup MeshConstants
	integer(KINT), parameter :: PLANE_SOLVER = 99 !<< problemKind parameter for quadrilateral panels @ingroup MeshConstants
	integer(KINT), parameter ::	MAX_POLYGON_SIDES = 20 !<< defines maximum allowable polygon size in a Voronoi mesh @ingroup MeshConstants
	integer(KINT), parameter ::	FREE_BOUNDARIES = 101 !<< boundary condition parameter for planar meshes @ingroup MeshConstants
	integer(KINT), parameter ::	PERIODIC_BOUNDARIES = 102 !<< boundary condition parameter for planar meshes @ingroup MeshConstants


	!> @defgroup MPIVariables MPI Variables
	!> @brief variables to define MPI computing environment
	integer(KINT), save :: numProcs = 1 !<< number of processess @ingroup MPIVariables
	integer(KINT), save :: procRank = 0 !<< process rank @ingroup MPIVariables


end module NumberKindsModule

