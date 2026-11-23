# Porting notes — QNX 8.0

What actually had to change to make moqlivecast build and run on QNX 8.0, and why.
Everything below was verified on QNX SDP 8.0.3 with the x86_64 target (QEMU) and
cross-checked for aarch64.

Source-level changes were merged upstream rather than kept as a patch stack; the
commit hashes are listed in [`patches/README.md`](../patches/README.md).

---

## 1. Summary

| Layer | Changes | Where |
|---|---|---|
| Build system | QNX branch for the OpenSSL `ExternalProject` | upstream `CMakeLists.txt` |
| Dependency | libuv 1.44.3 → 1.53.0 | upstream `3rdparty/libuv` |
| C source | 2 missing includes | upstream `logger/logger.c`, `moq_transport_client.h` |
| Toolchain flags | `-D_QNX_SOURCE`, `-liconv` | upstream `CMakeLists.txt` |

The application code itself needed **no functional changes**. The QUIC stack,
HTTP/3, WebTransport and MoQ logic compiled unmodified once the build and the two
includes were fixed.

---

## 2. Build-system issues

### 2.1 OpenSSL was silently built with the host compiler

QNX satisfies `UNIX` in CMake, so `OPENSSL_TARGET` was already correct
(`linux-x86_64` / `linux-aarch64`). The real problem was that `Configure` never
received `CC`, so OpenSSL fell back to the host `cc` and produced a Linux static
library. The mismatch only shows up at link time:

```
undefined reference to `__errno_location'
undefined reference to `__ctype_b_loc'
undefined reference to `getcontext'
undefined reference to `__isoc99_sscanf'
```

Fix (upstream `32cc938`): pass `CC`/`AR`/`RANLIB` explicitly, and drop what QNX
does not provide.

### 2.2 qcc does not parse `-MF`

OpenSSL's makefile invokes the compiler with `-MMD -MF <file>.d.tmp`. qcc's option
parser treats the dependency file name as a second input and fails:

```
cc: Can't specify -P, -C, -E, -c or -S with -o and have multiple files
```

Fix: a tiny wrapper (`scripts/qcc-nodep`) strips `-MMD/-MD/-MP/-MF/-MT/-MQ`
before calling qcc; the QNX branch passes it as `CC`.

### 2.3 Only `build_libs` can be built

`apps/` fails on QNX for the same `-MF` reason plus Linux-only headers. The QNX
branch therefore builds `build_libs` and installs by copying:

- `${OPENSSL_SRC_DIR}/include` (public headers, e.g. `e_ostime.h`)
- the generated headers from the build tree (overlay)
- `libssl.a`, `libcrypto.a`

Missing the first copy produced `openssl/e_ostime.h: No such file` (fixed in
`bfd9897`).

### 2.4 `link_libraries()` after a target has no effect

`link_libraries(iconv)` appended after `add_executable()` is a no-op — a silent
failure, not an error. Use `target_link_libraries(moqlivecast PRIVATE iconv)`.

---

## 3. Dependency issues

### 3.1 libuv version

The vendored libuv 1.44.3 targets QNX 7.x and fails on 8.0:

```
error: 'struct qtime_entry' has no member named 'nsec'
error: 'struct syspage_entry' has no member named 'new_cpuinfo'
```

QNX 8 changed the syspage/qtime layout. The fix is upstream PR #4801, which
landed **after v1.51.0**; v1.52.0 is the first release that contains it.
Upstream now vendors 1.53.0.

Verify quickly:

```bash
grep -n "qtime->nsec\|new_cpuinfo" 3rdparty/libuv/src/unix/qnx.c   # expect no output
```

### 3.2 iconv is a separate library on QNX

QNX libc has no iconv symbols; they live in `libiconv.so` and `iconv.h` ships with
SDP. The server uses `iconv_open`/`iconv`/`iconv_close` in
`moqlivecast/utils/stringex.cpp`, so QNX builds must link `-liconv`.

Do **not** try to map `libiconv_open` onto `iconv_open`: QNX's `iconv.h` already
uses the GNU-style mapping, and re-mapping produces undefined symbols.

### 3.3 OpenSSL must be linked statically

The target ships `libssl.so.3` (3.0.x). Dynamically linking the vendored 3.5.8
makes the loader resolve the system library at runtime, and the QUIC symbols
disappear. `no-shared` plus static archives avoids this entirely.

Reliable check (static archives carry no GLIBC version strings, so
`strings | grep GLIBC` is not a valid test):

```bash
$QNX_HOST/usr/bin/ntox86_64-nm libcrypto.a | grep -c __errno_location   # 0
$QNX_HOST/usr/bin/ntox86_64-nm libssl.a    | grep SSL_set_quic_tls_cbs  # T symbol
```

---

## 4. Source-level issues

### 4.1 `int64_t` is not implicitly available

```
logger/logger.c:40:8: error: unknown type name 'int64_t'
```

On Linux the include chain of `<sys/types.h>` happens to pull in `<stdint.h>`;
QNX does not guarantee it. Fixed by including `<stdint.h>` explicitly.

### 4.2 `sockaddr_in6` is incomplete in C++

```
uv.h:1239: error: field 'address6' has incomplete type 'sockaddr_in6'
```

Two independent causes:

1. `libuv`'s `uv.h` relies on `sockaddr_in6` being complete; including
   `<netinet/in.h>` before `<uv.h>` fixes the C++ translation unit.
2. QNX gates POSIX declarations behind extension macros. With `-std=c++14`
   (strict ANSI) the struct stays hidden. Either `-std=gnu++14` or
   `-D_QNX_SOURCE` fixes it; the port uses `-D_QNX_SOURCE` so the language
   standard does not change.

This only affects C++: C tolerates the incomplete type in some contexts, which is
why the C SDK compiled before the C++ tools did.

---

## 5. Runtime / deployment issues

| Issue | Detail | Workaround |
|---|---|---|
| No bridged networking on a cloud host | `mkqnximage`'s default QEMU setup wants `brctl` + `dnsmasq` | use `-netdev user` (slirp) with explicit `hostfwd` |
| QUIC needs a UDP forward | TCP forwards do not carry QUIC | `hostfwd=udp::4433-:4433` plus `hostfwd=tcp::4433-:4433` |
| `/system`, `/usr` are read-only IFS | cannot install packages or drop libraries at runtime | binaries, config and logs live under `/data` |
| `sshd` missing `sshd-auth` in the image | sshd exits, so `scp` is unavailable | transfer binaries over HTTP from the host (`curl http://10.0.2.2:8000/...`) |
| QEMU process dies with the SSH session | stdout is the console | run QEMU inside `tmux` |

---

## 6. What did **not** need changing

Worth stating explicitly, because it is the interesting result:

- no changes to the QUIC state machine, loss recovery, pacing, or congestion control
- no changes to HTTP/3 or WebTransport framing
- no changes to the MoQ layer (catalog, tracks, subscribe/publish)
- no changes to the RTMP / HTTP-FLV servers

io-sock provided enough POSIX surface (epoll, sockets, threads) that the network
code ran as-is. The port was a build-system and toolchain exercise, not a rewrite.

---

## 7. Verification performed

| Check | Result |
|---|---|
| `qcc` produces QNX ELF for x86_64 and aarch64 | ✅ `interpreter /usr/lib/ldqnx-64.so.2` |
| `libmoq_transport_client.a` builds | ✅ |
| `flv2moqtransport_client` links and pushes | ✅ |
| full server `moqlivecast` builds | ✅ |
| server runs in QEMU and listens on 4433 | ✅ `[wt-server] listening on 0.0.0.0:4433` |
| publish from a host client, play with `moq_player` | ✅ |
| reproducible from a clean clone | ✅ `bootstrap.sh` + `build.sh` |
