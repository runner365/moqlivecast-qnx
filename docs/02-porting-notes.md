# Porting notes — Linux assumptions vs QNX 8.0

Living document. Every row is something that has to be checked on target; the
status column is the truth of the moment, not the plan.

## Environment

* QNX SDP 8.0 has **no macOS host**. Cross-compile from Linux (VM or container).
* QNX 8.0 always uses **io-sock** (the NetBSD-derived stack). `io-pkt` is gone;
  code written for QNX 7.1 with `io-pkt` needs the io-sock migration guide.
* `qcc` is a driver; the target is `-Vgcc_ntoaarch64le` (or `gcc_ntox86_64`).
  CMake selects it via `CMAKE_<LANG>_COMPILER_TARGET`.

## Known Linux-isms in the upstream tree

| area | upstream assumption | QNX 8.0 reality | status |
|---|---|---|---|
| event loop | libuv | libuv 1.51+ has QNX 8 support ([PR #4801](https://github.com/libuv/libuv/pull/4801), 2025-06); **needs a build recipe** | ☐ |
| I/O readiness | epoll / `EPOLLET` | io-sock provides epoll, but edge-trigger semantics and `EPOLLRDHUP` need verification | ☐ |
| eventfd / timerfd | Linux-only syscalls | io-sock has eventfd/timerfd; verify or fall back to `pulse` + `MsgReceive` | ☐ |
| batched send | `sendmmsg` | not available; loop over `sendmsg` or use `sendmsg` with `MSG_NOSIGNAL` | ☐ |
| UDP GSO / corking | `UDP_SEGMENT`, `TCP_CORK` | absent; pacing must absorb the cost (upstream already has `quic/pacing_send.c`) | ☐ |
| `SO_REUSEPORT` | used for listener sharding | behaviour differs; single listener + threads is the safe path | ☐ |
| CPU affinity | `sched_setaffinity` | `ThreadCtl(_NTO_TCTL_RUNMASK…)` — wrapped in `port/qnx/` | ☑ |
| thread priority | `pthread_setschedparam` | same POSIX API, but needs `PROCMGR_AID_PRIORITY` for non-root | ☑ |
| clock | `CLOCK_MONOTONIC` | identical; keep it out of `CLOCK_REALTIME` paths | ☑ |
| TLS | OpenSSL from the distro | SDP ships OpenSSL 3 (verify the exact package); else build via a qnx-ports style recipe | ☐ |
| YAML | yaml-cpp from the distro | **no yaml-cpp port in qnx-ports** — either vendor it or add the recipe (upstream contribution) | ☐ |
| `/proc` | metrics parsing | QNX has `/proc` but a smaller surface; don't rely on it for stats | ☐ |
| signal handling | `signalfd` | not available; use `sigwait` on a dedicated thread | ☐ |

## Sequencing

1. **Compile only** (`-c`) the C SDK against the SDP headers. This surfaces the
   include/syscall gaps in hours rather than days.
2. **Link + run** a UDP echo (upstream has `quic/quic_echo_server.c`) on QEMU.
3. **TLS handshake** through the C SDK.
4. **Media push** with the test pattern source.
5. **Real-time layer**: priority map, affinity, APS partition.
6. **Evidence**: latency + jitter under netem.

## Risks

| risk | mitigation |
|---|---|
| libuv event loop misbehaves on io-sock | fallback: upstream already has a poll-based path; a `posix-poll` backend is 200 lines |
| OpenSSL missing from SDP | build from source with the `qnx-ports` recipe pattern; budget 2 days |
| camera driver on RPi5 blocks progress | test pattern source is a first-class deliverable, not a fallback |
| upstream moves while porting | pinned commit in `scripts/bootstrap.sh`; rebase weekly, not daily |
| QEMU networking flaky | also keep a `-netdev user` config with explicit hostfwd; document both |

## Checklist

- [ ] `scripts/env.sh` sources cleanly on Linux
- [ ] `scripts/build.sh` configures with the QNX toolchain
- [ ] C SDK compiles (`-c`) against SDP headers
- [ ] UDP echo runs in QEMU
- [ ] TLS handshake completes
- [ ] test-pattern push plays in the browser player
- [ ] priority/affinity layer applied and verified with `pidin`
- [ ] APS partition configured
- [ ] latency + jitter measured under netem
- [ ] demo video recorded
