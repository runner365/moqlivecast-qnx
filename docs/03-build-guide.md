# Build guide — cross-compiling for QNX 8.0

Everything here runs on an **x86_64 Linux host**. The resulting binaries run on a
QNX target (QEMU or hardware).

> QNX SDP 8.0 has no ARM-host and no macOS build, so an x86_64 Linux machine is
> required. This port was developed on Ubuntu 22.04 against QNX SDP 8.0.3.

---

## 0. Prerequisites

| Item | Requirement |
|---|---|
| Host | x86_64 Linux (Ubuntu 22.04 verified) |
| QNX SDP | 8.0.3, installed at `~/qnx800` |
| Disk | ≥ 60 GB free (the OpenSSL build alone needs ~2 GB) |
| RAM | 8 GB recommended (4 GB works) |

```bash
echo 'source ~/qnx800/qnxsdp-env.sh' >> ~/.bashrc
source ~/qnx800/qnxsdp-env.sh
echo $QNX_TARGET     # .../target/qnx
echo $QNX_HOST       # .../host/linux/x86_64
```

---

## 1. Get the code

```bash
git clone https://github.com/runner365/moqlivecast-qnx.git
cd moqlivecast-qnx
./scripts/bootstrap.sh          # fetches upstream by URL at a pinned commit
```

Upstream is referenced by URL and checked out at a fixed commit; its history is
never copied into this repository.

---

## 2. Build

```bash
source ~/qnx800/qnxsdp-env.sh
./scripts/build.sh x86_64 flv2moqtransport_client
```

Targets:

| Target | Output |
|---|---|
| `moq_transport_client` | `libmoq_transport_client.a` |
| `flv2moqtransport_client` | `bin/flv2moqtransport_client` |
| `moqlivecast` | `bin/moqlivecast` (the full server) |

Result:

```
build-qnx-x86_64/bin/moqlivecast
build-qnx-x86_64/bin/flv2moqtransport_client
```

For the ARM target (Raspberry Pi 5):

```bash
./scripts/build.sh aarch64 moqlivecast
```

---

## 3. What the build actually does

### 3.1 libuv

Upstream vendors **libuv 1.53.0**, which contains the QNX 8 fixes (syspage and
qtime structures changed between QNX 7 and 8). No action is required.

`scripts/fetch-deps.sh` exists only as a guard: if a future pin moves libuv back
below 1.52, it downloads and swaps in a newer release. On the current pin it is a
no-op and prints `libuv minor=53, already satisfied`.

### 3.2 OpenSSL 3.5.8

Upstream vendors OpenSSL 3.5.8 and its `CMakeLists.txt` has a QNX branch that:

- passes `CC=qcc -V<variant>`, `AR`, `RANLIB` to `Configure`
- disables components QNX does not provide: `no-tests no-asm no-async no-afalgeng`
- builds only `build_libs` (the `apps/` targets fail because qcc does not parse `-MF`)
- installs the static libraries plus the **full** header tree into
  `build-qnx-<arch>/openssl_install`

`cmake --build` drives this automatically; a separate OpenSSL step is **not**
needed.

`scripts/build-openssl.sh` is kept as a **manual fallback** for debugging the
OpenSSL step in isolation (it reproduces the same configuration by hand).

Why OpenSSL 3.5 specifically: the code uses `SSL_set_quic_tls_cbs`, which only
exists in 3.5+. QNX SDP ships 3.0.x, so the vendored 3.5.8 must be used and must
be linked **statically** (otherwise the runtime loader picks the system
`libssl.so.3` and the QUIC symbols disappear).

### 3.3 yaml-cpp

Built by CMake as an ordinary dependency of the server. No separate step.

`ports/yaml-cpp/` is unrelated to building this project: it is a `qnx-ports`
recipe contributed so that other QNX projects can install yaml-cpp system-wide.

---

## 4. Verify the toolchain

```bash
qcc -Vgcc_ntoaarch64le -o /tmp/h /tmp/h.c && file /tmp/h
```

Expected:

```
ELF 64-bit LSB ... ARM aarch64 ... interpreter /usr/lib/ldqnx-64.so.2
```

`/usr/lib/ldqnx-64.so.2` is the QNX dynamic loader. If you see
`ld-linux-x86-64.so.2`, the host compiler was used by mistake.

Verify a built artifact:

```bash
file build-qnx-x86_64/bin/moqlivecast | grep -o "interpreter [^,]*"

$QNX_HOST/usr/bin/ntox86_64-nm \
  build-qnx-x86_64/openssl_install/lib/libcrypto.a 2>/dev/null \
  | grep -c "__errno_location"      # must print 0

$QNX_HOST/usr/bin/ntox86_64-nm \
  build-qnx-x86_64/openssl_install/lib/libssl.a 2>/dev/null \
  | grep SSL_set_quic_tls_cbs       # must print a T symbol
```

The `nm` checks are the reliable way to tell a QNX-built OpenSSL from a host-built
one; `strings | grep GLIBC` is **not** reliable for static archives.

---

## 5. Deploy to the QNX target

With QEMU user-mode networking, the guest reaches the host at `10.0.2.2`:

```bash
# host
cp build-qnx-x86_64/bin/moqlivecast ~/share/
cd ~/share && python3 -m http.server 8000
```

```bash
# QNX console
cd /data/moq
curl -O http://10.0.2.2:8000/moqlivecast
chmod +x moqlivecast
```

`/system` and `/usr` are read-only IFS; `/data` is writable. Binaries,
configuration and logs belong under `/data`.

For TCP/UDP services to be reachable from the host, forward the ports when
starting QEMU:

```bash
-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080,hostfwd=udp::4433-:4433,hostfwd=tcp::4433-:4433
```

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `qtime_entry has no member nsec` | vendored libuv < 1.52 | update the pinned commit, or run `scripts/fetch-deps.sh` |
| `undefined reference to __errno_location` | OpenSSL was built with the host gcc | check the QNX branch in `CMakeLists.txt`; the `nm` test above tells you which library you have |
| `Can't specify -c with -o and have multiple files` | qcc does not parse `-MF` | use `scripts/qcc-nodep` as `CC` (the QNX branch does this) |
| `undefined reference to engine_load_afalg_int` | stale objects after changing Configure options | remove `build-qnx-*/openssl_ext-prefix` and rebuild |
| `field 'address6' has incomplete type` | QNX gates POSIX declarations behind extension macros | build with `-D_QNX_SOURCE` (handled by `scripts/build.sh`) |
| `openssl/e_ostime.h: No such file` | header install copied only generated headers | fixed upstream (`bfd9897`); update the pinned commit |
| downloaded file is HTML | HTTP server returned 404 | `curl -s -o /dev/null -w "%{http_code}"` before downloading |
