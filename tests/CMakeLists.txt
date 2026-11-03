add_executable(test_platform test_platform.c)
target_link_libraries(test_platform PRIVATE moq_qnx_port)

add_test(NAME platform COMMAND test_platform)
