# 构建指南：在 Linux 上交叉编译 QNX 8.0 目标

本文档记录把 moqlivecast 的 C SDK 交叉编译到 QNX 8.0 的完整步骤。所有命令都在
**x86_64 Linux 宿主机**上执行，产物在 QNX 目标（QEMU 或开发板）上运行。

> 为什么必须是 x86_64 Linux：QNX SDP 8.0 不支持 ARM 宿主，也不支持 macOS。

---

## 0. 环境要求

| 项 | 要求 |
|---|---|
| 宿主机 | x86_64 Linux（Ubuntu 22.04 已验证） |
| QNX SDP | 8.0.3，装在 `~/qnx800` |
| 磁盘 | ≥ 60 GB 可用 |
| 内存 | ≥ 8 GB 推荐（4 GB 可跑） |

环境变量：

```bash
echo 'source ~/qnx800/qnxsdp-env.sh' >> ~/.bashrc
source ~/qnx800/qnxsdp-env.sh
echo $QNX_TARGET     # .../target/qnx
echo $QNX_HOST       # .../host/linux/x86_64
```

---

## 1. 取代码

```bash
git clone https://github.com/runner365/moqlivecast-qnx.git
cd moqlivecast-qnx
./scripts/bootstrap.sh          # 按 URL 拉上游，打到 pinned commit
```

结果：上游源码在 `upstream/`（已在 `.gitignore` 中）。

### 一键构建（推荐）

```bash
source ~/qnx800/qnxsdp-env.sh
./scripts/build.sh x86_64 flv2moqtransport_client
```

脚本做的事：

| 脚本 | 内容 |
|---|---|
| `scripts/fetch-deps.sh` | 把 vendored libuv 换成 ≥1.52（写死版本号，可复现） |
| `scripts/build.sh` | CMake 配置（含 `-D_QNX_SOURCE`）+ 多目标构建 |

**OpenSSL 的交叉编译不用手动做**：`patches/0002-qnx-openssl-build.patch` 修改了上游
`CMakeLists.txt`，让 `openssl_ext` 目标在 QNX 下用 `qcc` 编译（传 `CC`/`AR`/`RANLIB`，
加 `no-tests no-asm no-async no-afalgeng`，用 `make build_libs` 跳过 apps）。
`cmake --build` 会自动驱动它。

`scripts/build-openssl.sh` 仅作为手动排查工具保留（当 CMake 那一步出问题时，可以单独跑它定位）。

下面是每一步的原理说明，脚本出问题时对照阅读。

---

## 2. 依赖一：libuv（必须 ≥ 1.52）

**上游自带的 libuv 1.44.3 编不过 QNX 8**，因为它按 QNX 7.x 的 syspage 结构写：

```
error: 'struct qtime_entry' has no member named 'nsec'
error: 'struct syspage_entry' has no member named 'new_cpuinfo'
```

QNX 8 的适配在上游 PR #4801 里，**v1.51.0 还没包含，1.52.0 起才有**。

```bash
cd upstream/3rdparty
mv libuv libuv-1.44.3

curl -L -o /tmp/libuv.tar.gz \
  https://github.com/libuv/libuv/archive/refs/tags/v1.53.0.tar.gz
tar -xzf /tmp/libuv.tar.gz -C /tmp
mv /tmp/libuv-1.53.0 libuv

# 验证
grep -E "UV_VERSION_(MAJOR|MINOR)" libuv/include/uv/version.h
grep -n "qtime->nsec\|new_cpuinfo" libuv/src/unix/qnx.c   # 应该没有输出
```

---

## 3. 依赖二：OpenSSL 3.5（含 QUIC API）

**为什么必须自己编**：代码使用 `SSL_set_quic_tls_cbs`，这是 **OpenSSL 3.5 才有的 QUIC API**。
QNX SDP 自带的是 3.0.x，运行时会出现 `undefined symbol`。

**为什么必须用静态库**：系统里已有 `libssl.so.3`（3.0.x），动态链接会 SONAME 冲突，
程序会加载到旧库。静态链接把符号直接打进可执行文件。

**为什么必须用包装脚本**：qcc 不认识 `-MF`，会把依赖文件名当成第二个输入文件，报
`Can't specify -c with -o and have multiple files`。

```bash
mkdir -p ~/bin
cat > ~/bin/qcc-nodep <<'EOF'
#!/bin/bash
# 过滤 qcc 不认识的依赖生成参数
args=(); skip=0
for a in "$@"; do
  if [ $skip -eq 1 ]; then skip=0; continue; fi
  case "$a" in
    -MMD|-MD|-MP) continue ;;
    -MF|-MT|-MQ)  skip=1; continue ;;
  esac
  args+=("$a")
done
exec qcc "${args[@]}"
EOF
chmod +x ~/bin/qcc-nodep
```

配置并编译：

```bash
cd upstream/3rdparty/openssl-3.5.8
rm -f Makefile configdata.pm

./Configure no-shared no-tests no-asm no-async no-afalgeng \
  --prefix=$HOME/qnx-openssl/x86_64 \
  --openssldir=/data/ssl \
  CC="$HOME/bin/qcc-nodep -Vgcc_ntox86_64" \
  AR="ntox86_64-ar" RANLIB="ntox86_64-ranlib" \
  linux-x86_64

make -j4 build_libs
```

参数说明：

| 参数 | 原因 |
|---|---|
| `no-shared` | 静态库，避免与系统 3.0.x 的 SONAME 冲突 |
| `no-asm` | 避开汇编差异，先保证能编过 |
| `no-async` | QNX 没有 `getcontext`/`makecontext` |
| `no-afalgeng` | AF_ALG 是 Linux 内核的加密接口 |
| `build_libs` | 只编库，`apps/` 里的命令行工具不需要（且会因 qcc 参数问题失败） |

验证：

```bash
$QNX_HOST/usr/bin/ntox86_64-nm libcrypto.a 2>/dev/null \
  | grep -cE "__errno_location|__ctype_b_loc|__isoc99_sscanf"     # 必须是 0

$QNX_HOST/usr/bin/ntox86_64-nm libssl.a 2>/dev/null | grep SSL_set_quic_tls_cbs
# 期望：0000000000xxxxxx T SSL_set_quic_tls_cbs
```

> ⚠️ **改了 Configure 选项必须 `make clean`**。OpenSSL 的 Makefile 不跟踪编译宏变化，
> 旧 `.o` 会被复用，导致上一轮（比如启用了 afalg）的符号残留。

---

## 4. 配置并编译

```bash
cd moqlivecast-qnx

cmake -S upstream -B build-qnx-x86_64 \
  -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/toolchain-qnx800-x86_64.cmake \
  -DCMAKE_C_FLAGS="-D_QNX_SOURCE" \
  -DCMAKE_CXX_FLAGS="-D_QNX_SOURCE"

cmake --build build-qnx-x86_64 --target moq_transport_client -j4
```

### 为什么需要 `-D_QNX_SOURCE`

QNX 的头文件把 `sockaddr_in6` 这类 POSIX/BSD 定义藏在扩展宏后面。C++ 严格模式下
（`-std=c++14`）会报：

```
error: field 'address6' has incomplete type 'sockaddr_in6'
```

验证（三条命令的差异）：

```bash
qcc -Vgcc_ntox86_64 -std=c++14   -c t.cpp   # 失败
qcc -Vgcc_ntox86_64 -std=gnu++14 -c t.cpp   # 成功
qcc -Vgcc_ntox86_64 -std=c++14 -D_QNX_SOURCE -c t.cpp   # 成功
```

选 `_QNX_SOURCE`：不改变语言标准，且是 QNX 平台的正统做法。

---

## 5. 构建目标

```bash
# 核心库
cmake --build build-qnx-x86_64 --target moq_transport_client -j4

# 可执行文件
cmake --build build-qnx-x86_64 --target flv2moqtransport_client -j4
```

产物：

```
build-qnx-x86_64/libmoq_transport_client.a
build-qnx-x86_64/bin/flv2moqtransport_client
```

验证是 QNX 二进制：

```bash
file build-qnx-x86_64/bin/flv2moqtransport_client | grep -o "interpreter [^,]*"
# interpreter /usr/lib/ldqnx-64.so.2
```

---

## 6. 部署到 QNX 目标

当前使用的通道（QEMU slirp 网络，客户机通过 `10.0.2.2` 访问宿主机）：

```bash
# 宿主机
mkdir -p ~/share
cp build-qnx-x86_64/bin/flv2moqtransport_client ~/share/
cd ~/share && python3 -m http.server 8000
```

```bash
# QNX 控制台
cd /data/moq
curl -o flv2moq http://10.0.2.2:8000/flv2moqtransport_client
chmod +x flv2moq
./flv2moq --help
```

> QNX 的 `/system`、`/usr` 是只读 IFS，只有 `/data` 可写。程序、配置、日志都放 `/data/`。

---

## 7. 已知问题速查

| 现象 | 根因 | 解决 |
|---|---|---|
| `qtime_entry has no member nsec` | libuv < 1.52 按 QNX 7 写的 | 升级 libuv 到 1.53 |
| `undefined reference to __errno_location` | OpenSSL 用宿主 gcc 编的 | 手工用 qcc 重编（第 3 节） |
| `Can't specify -c with -o and have multiple files` | qcc 不认 `-MF` | 用 `qcc-nodep` 包装脚本 |
| `undefined reference to engine_load_afalg_int` | 改 Configure 后没 `make clean` | `make clean` 全量重编 |
| `field 'address6' has incomplete type` | QNX 扩展被严格模式屏蔽 | `-D_QNX_SOURCE` |
| `unknown type name 'int64_t'` | Linux 上间接包含，QNX 不保证 | 显式 `#include <stdint.h>` |
| 下载到 HTML 而不是二进制 | HTTP 服务 404 | `curl -s -o /dev/null -w "%{http_code}"` 先验证 200 |
