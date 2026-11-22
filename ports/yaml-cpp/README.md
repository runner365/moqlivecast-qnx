# yaml-cpp

[yaml-cpp](https://github.com/jbeder/yaml-cpp) 是一个 YAML 1.2 的 C++ 解析器与生成器。
它是 QNX 生态里缺失的常见依赖之一（`qnx-ports` 有 `libyaml`（C 库），但没有 `yaml-cpp`）。

**NOTE**: QNX ports are only supported from a Linux host operating system.

Use `$(nproc)` instead of `4` after `JLEVEL=` and `-j` if you want to use the maximum
number of cores to build this project.

To install the library files at a specific location (e.g. `/tmp/staging`) use options
`INSTALL_ROOT_nto=<staging-install-folder>` and `USE_INSTALL_ROOT=true` with the build command.

## Compile the port for QNX in a Docker container

Pre-requisite: Install Docker on Ubuntu https://docs.docker.com/engine/install/ubuntu/

```bash
# Create a workspace
mkdir -p ~/qnx_workspace && cd ~/qnx_workspace
git clone https://github.com/qnx-ports/build-files.git

# Build the Docker image and create a container
cd build-files/docker
./docker-build-qnx-image.sh
./docker-create-container.sh

# Now you are in the Docker container

# Source qnxsdp-env.sh in
source ~/qnx800/qnxsdp-env.sh
cd ~/qnx_workspace

# Clone yaml-cpp
git clone https://github.com/jbeder/yaml-cpp.git

# Build yaml-cpp
make -C build-files/ports/yaml-cpp install -j4
```

## Compile the port for QNX on Ubuntu host

```bash
# Clone the repos
mkdir -p ~/qnx_workspace && cd qnx_workspace
git clone https://github.com/qnx-ports/build-files.git
git clone https://github.com/jbeder/yaml-cpp.git

# source qnxsdp-env.sh
source ~/qnx800/qnxsdp-env.sh

# Build yaml-cpp
make -C build-files/ports/yaml-cpp install -j4
```

## Output

Both static and shared libraries are produced under the staging area:

```
$QNX_TARGET/<cpuvardir>/usr/local/lib/libyaml-cpp.a
$QNX_TARGET/<cpuvardir>/usr/local/lib/libyaml-cpp.so
$QNX_TARGET/<cpuvardir>/usr/local/include/yaml-cpp/
```

`BUILD_SHARED_LIBS=OFF` builds static only:

```bash
make -C build-files/ports/yaml-cpp install -j4 BUILD_SHARED_LIBS=OFF
```

## Consume it from another project

```cmake
find_package(yaml-cpp REQUIRED)
target_link_libraries(my_app PRIVATE yaml-cpp::yaml-cpp)
```

or, for a plain `qcc` build:

```bash
qcc -Vgcc_ntoaarch64le -I$QNX_TARGET/aarch64le/usr/local/include \
    my_app.c $QNX_TARGET/aarch64le/usr/local/lib/libyaml-cpp.a
```

## Tested with

- QNX SDP 8.0 (QNX OS 8.0.3)
- yaml-cpp v0.8.0
- Host: Ubuntu 22.04 x86_64
- Targets: `nto-aarch64-le`, `nto-x86_64-o`
