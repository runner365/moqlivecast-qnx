# QNX publisher demo (`apps/qnx-publisher/`)

The QNX-side half of the demo. It must do three things and nothing else:

1. produce a frame source (test pattern first, camera later),
2. push it through the upstream **C SDK** over QUIC,
3. timestamp every frame so glass-to-glass latency can be measured.

## Why the C SDK and not the server

Route A: the QNX box is the *device*. The C SDK (`moq_transport_client/` for
moq-transport draft-22, `moqlite/` for moq-lite-06) is the smallest surface that
still exercises the hard parts — sockets, timers, TLS, pacing — and it is what a
real product would embed.

## Milestones

| M | what | proves |
|---|---|---|
| M1 | test pattern + timestamp overlay, push to a PC server, play in a browser | the stack runs on QNX at all |
| M2 | 1 kHz "servo" thread at `SCHED_FIFO` prio 20 alongside the publisher | priority + affinity layer works |
| M3 | camera (RPi5 `libcamera` / `devc-*`) replacing the test pattern | a real device story |
| M4 | latency histogram in the frame header, exported to `/dev/shmem` | the numbers |

## Frame timestamp format

Every frame carries `uint64 moq_qnx_mono_ns()` of the sender. The player prints
`now - ts` per frame; the benchmark harness reads those lines. Keep the clock
monotonic and never mix it with `CLOCK_REALTIME`.

```
[frame] seq=12345 ts=981273645123456 len=48213 key=0
```

## Build

Compiled from the top-level `CMakeLists.txt` with the QNX toolchain; the
upstream C SDK is built by `scripts/build.sh` into `build-qnx-<arch>/stage`.
