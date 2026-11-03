# Dev/host build for the QNX port layer.
#
# The *target* build is driven by scripts/build.sh, which configures the
# upstream tree directly with cmake/toolchain-qnx800-<arch>.cmake. This file
# exists so `port/qnx/` and its tests can be built and run on the host
# (no SDP required), which keeps the porting layer honest.
cmake_minimum_required(VERSION 3.16)
project(moqlivecast_qnx_port LANGUAGES C)

option(MOQ_QNX_BUILD_TESTS "Build host tests for the port layer" ON)

add_subdirectory(port/qnx)

if(MOQ_QNX_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
