# QNX 8.0 (aarch64le) toolchain for CMake.
#
#   export QNX_SDP=/opt/qnx800
#   source "$QNX_SDP/qnxsdp-env.sh"
#   cmake -B build-qnx-aarch64 -S upstream \
#         -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-qnx800-aarch64.cmake
#
# qcc is a driver: the target is selected with -V<variant>. CMake forwards
# CMAKE_<LANG>_COMPILER_TARGET as -V<value>, so that value must be the qcc
# variant name, not a GNU triplet.

set(CMAKE_SYSTEM_NAME QNX)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(QNX_ARCH gcc_ntoaarch64le)

set(CMAKE_C_COMPILER   qcc)
set(CMAKE_CXX_COMPILER qcc)
set(CMAKE_ASM_COMPILER qcc)

set(CMAKE_C_COMPILER_TARGET   ${QNX_ARCH})
set(CMAKE_CXX_COMPILER_TARGET ${QNX_ARCH}_cxx)
set(CMAKE_ASM_COMPILER_TARGET ${QNX_ARCH})

if(NOT DEFINED ENV{QNX_TARGET})
  message(FATAL_ERROR "QNX_TARGET is not set. Source $QNX_SDP/qnxsdp-env.sh first.")
endif()

set(CMAKE_SYSROOT $ENV{QNX_TARGET})
set(CMAKE_FIND_ROOT_PATH
    $ENV{QNX_TARGET}
    $ENV{QNX_TARGET}/usr
)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# QNX 8.0 ships GCC 12; keep the C++ standard the upstream CMakeLists expects.
set(CMAKE_CXX_STANDARD 14 CACHE STRING "" FORCE)
