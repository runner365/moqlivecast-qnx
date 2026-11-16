# 上游改动记录（源码级 QNX 支持）

本仓库**不携带源码补丁**：QNX 8.0 所需的源码改动已经直接合入上游
[moqlivecast](https://github.com/runner365/moqlivecast)。

本文件记录这些改动的来源，供评审核对。

## 已合入上游

| 内容 | 上游 commit | 涉及文件 |
|---|---|---|
| 补全 POSIX 头文件（`int64_t` / `sockaddr_in6`） | [`ba473628`](https://github.com/runner365/moqlivecast/commit/ba473628858d) | `logger/logger.c`、`moq_transport_client/include/moq_transport_client.h` |
| 用 qcc 交叉编译 OpenSSL（QNX 分支） | [`32cc9383`](https://github.com/runner365/moqlivecast/commit/32cc93834c0d) | `CMakeLists.txt` |
| 安装完整 OpenSSL 头文件树（`e_ostime.h` 缺失） | [`bfd98970`](https://github.com/runner365/moqlivecast/commit/bfd9897071d1) | `CMakeLists.txt` |

`scripts/bootstrap.sh` 检出**固定 commit**（见脚本里的 `UPSTREAM_REF`），保证可复现。

## 为什么这两处必须在上游修

### 1. `int64_t` 不完整

```text
logger.c:40:8: error: unknown type name 'int64_t'
```

Linux 上 `<sys/types.h>` 的包含链会间接带出 `<stdint.h>`，QNX 不保证。
这是代码的隐式依赖——正确做法是显式包含，而不是在移植层绕。

### 2. OpenSSL 被编成了 Linux 版

```text
undefined reference to `__errno_location'
undefined reference to `__ctype_b_loc'
undefined reference to `getcontext'
```

QNX 在 CMake 里同样满足 `UNIX`，所以 `OPENSSL_TARGET` 会正确选成
`linux-x86_64` / `linux-aarch64`——**真正的问题是 `Configure` 没有收到 `CC`**，
OpenSSL 于是退回系统的 `cc`（gcc），编出一份 Linux 静态库。

修法：

- 显式传 `CC=qcc -V<variant>`、`AR`、`RANLIB`
- 关闭 QNX 上不存在的组件：`no-tests no-asm no-async no-afalgeng`
- 只构建 `build_libs`（apps 会失败：qcc 不解析 `-MF`）

## 保留的兼容逻辑

`scripts/bootstrap.sh` 仍支持 `patches/*.patch`，并且是**幂等**的：

- 补丁已在源码中 → 跳过
- 补丁未应用 → 打上
- 打不上（冲突）→ 报错退出

这个机制留给未来的实验性改动：需要临时偏离上游时，把补丁放进 `patches/` 即可，
不会和上游冲突。
