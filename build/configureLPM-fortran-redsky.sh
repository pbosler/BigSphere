#!/bin/bash

export CC=mpicc
export CXX=mpicxx
export FC=mpif90

export NETCDF=/ascldap/users/pabosle/installs/netcdf-4.3.2

export SOURCE_ROOT=$HOME/lpm-v2/fortran

rm -rf CMakeCache.txt
rm -rf CMakeFiles/

cmake \
	-D CMAKE_BUILD_TYPE:STRING=RELEASE \
	-D CMAKE_INSTALL_PREFIX=$SOURCE_ROOT/install \
	$SOURCE_ROOT