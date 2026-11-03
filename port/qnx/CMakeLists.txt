# Portable QNX platform layer. Builds on the host too (stubs), so it can be
# unit-tested before the SDP is installed.
add_library(moq_qnx_port STATIC qnx_platform.c)
target_include_directories(moq_qnx_port PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

if(CMAKE_SYSTEM_NAME STREQUAL "QNX")
  target_link_libraries(moq_qnx_port PUBLIC socket)
endif()
