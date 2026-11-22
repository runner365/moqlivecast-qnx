ifndef QCONFIG
QCONFIG=qconfig.mk
endif
include $(QCONFIG)

include $(MKFILES_ROOT)/qmacros.mk

# Prevent qtargets.mk from re-including qmacros.mk
define VARIANT_TAG
endef

NAME = yaml-cpp

# Upstream source is expected next to build-files in the workspace:
#   ~/qnx_workspace/{build-files,yaml-cpp}
QNX_PROJECT_ROOT ?= $(PRODUCT_ROOT)/../../yaml-cpp

#$(INSTALL_ROOT_$(OS)) is pointing to $QNX_TARGET
#by default, unless it was manually re-routed to
#a staging area by setting both INSTALL_ROOT_nto
#and USE_INSTALL_ROOT
INSTALL_ROOT ?= $(INSTALL_ROOT_$(OS))

#A prefix path to use **on the target**. This is
#different from INSTALL_ROOT, which refers to a
#installation destination **on the host machine**.
PREFIX ?= /usr/local

#choose Release or Debug
CMAKE_BUILD_TYPE ?= Release

#override 'all' target to bypass the default QNX build system
ALL_DEPENDENCIES = yaml_cpp_all
.PHONY: yaml_cpp_all install check clean

include $(MKFILES_ROOT)/qtargets.mk

#Search paths for all of CMake's find_* functions --
#headers, libraries, etc.
CMAKE_FIND_ROOT_PATH := $(QNX_TARGET);$(QNX_TARGET)/$(CPUVARDIR);$(INSTALL_ROOT)/$(CPUVARDIR)

#Path to CMake modules installed by other packages
CMAKE_MODULE_PATH := $(QNX_TARGET)/$(CPUVARDIR)/$(PREFIX)/lib/cmake;$(INSTALL_ROOT)/$(CPUVARDIR)/$(PREFIX)/lib/cmake

#Headers from INSTALL_ROOT need to be made available by default
#because CMake and pkg-config do not necessarily add it automatically
#if the include path is "default"
CFLAGS += $(FLAGS) \
          -I$(QNX_TARGET)/$(CPUVARDIR)/$(PREFIX)/include \
          -I$(INSTALL_ROOT)/$(CPUVARDIR)/$(PREFIX)/include \
          -D_QNX_SOURCE
LDFLAGS += -Wl,--build-id=md5 -lm -lsocket

BUILD_SHARED_LIBS ?= ON

# yaml-cpp 0.7+ uses YAML_BUILD_SHARED_LIBS; older releases used the
# generic BUILD_SHARED_LIBS. Pass both so either layout works.
CMAKE_ARGS = -DCMAKE_TOOLCHAIN_FILE=$(PROJECT_ROOT)/qnx.nto.toolchain.cmake \
             -DCMAKE_SYSTEM_PROCESSOR=$(CPUVARDIR) \
             -DCMAKE_C_FLAGS="$(CFLAGS)" \
             -DCMAKE_CXX_FLAGS="$(CFLAGS)" \
             -DCMAKE_EXE_LINKER_FLAGS="$(LDFLAGS)" \
             -DCMAKE_CXX_COMPILER_TARGET=gcc_nto$(CPUVARDIR) \
             -DCMAKE_C_COMPILER_TARGET=gcc_nto$(CPUVARDIR) \
             -DCMAKE_INSTALL_PREFIX=$(INSTALL_ROOT) \
             -DCMAKE_INSTALL_LIBDIR=$(CPUVARDIR)/$(PREFIX)/lib \
             -DCMAKE_INSTALL_BINDIR=$(CPUVARDIR)/$(PREFIX)/bin \
             -DCMAKE_INSTALL_INCLUDEDIR=$(CPUVARDIR)/$(PREFIX)/include \
             -DCMAKE_MODULE_PATH="$(CMAKE_MODULE_PATH)" \
             -DCMAKE_FIND_ROOT_PATH="$(CMAKE_FIND_ROOT_PATH)" \
             -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
             -DBUILD_SHARED_LIBS=$(BUILD_SHARED_LIBS) \
             -DYAML_BUILD_SHARED_LIBS=$(BUILD_SHARED_LIBS) \
             -DYAML_CPP_BUILD_TESTS=OFF \
             -DYAML_CPP_BUILD_TOOLS=OFF \
             -DYAML_CPP_BUILD_CONTRIB=OFF \
             -DYAML_CPP_INSTALL=ON

MAKE_ARGS ?= -j $(firstword $(JLEVEL) 1)

ifndef NO_TARGET_OVERRIDE
yaml_cpp_all:
	@mkdir -p build
	@cd build && cmake $(CMAKE_ARGS) $(QNX_PROJECT_ROOT)
	@cd build && make VERBOSE=1 all $(MAKE_ARGS)

install check: yaml_cpp_all
	@echo Installing...
	@cd build && make VERBOSE=1 install $(MAKE_ARGS)
	@echo Done.

clean iclean spotless:
	rm -rf build
endif
