# QNX 8.0 platform layer

Everything in this directory exists because the upstream stack is written
against Linux/glibc assumptions. Keep it small, keep it auditable, and keep
every `#if defined(__QNX__)` branch next to the Linux path it replaces.

## What is here

| file | purpose |
|---|---|
| `qnx_platform.h/.c` | scheduling priority, CPU affinity, monotonic clock |
| `README.md` | this file — the running list of porting decisions |

## Design rules

1. **No QNX headers leak into upstream code.** Upstream files gain at most a
   `#include "qnx_platform.h"` plus a call; everything else stays in `port/qnx/`.
2. **The layer compiles on Linux too** (stub implementations), so it can be
   unit-tested on the host before the SDP is even installed.
3. **Priority numbers are named, not magic.** Servo/safety > capture/encode >
   QUIC I/O > stats/logging. See `MOQ_QNX_PRIO_*` in the header.

## Priority map (route A)

| thread / process | policy | prio | why |
|---|---|---|---|
| servo loop (demo) | `SCHED_FIFO` | 20 | must never wait on media |
| capture + encode | `SCHED_FIFO` | 10 | deadline is the frame interval |
| QUIC send/recv | `SCHED_FIFO` | 5 | network jitter is expected, bounded |
| stats / logging | `SCHED_OTHER` | — | must never run inside a deadline |

Run the media pipeline inside an APS partition with a hard budget so that a
burst cannot eat the servo loop's slack even if a priority is misconfigured:

```sh
# on target, once, after boot
aps create -n media -p 30        # 30 % of one CPU for the media partition
aps attach <media-pid> media
```

## Upstream relationship

Patches in `patches/` stay minimal and are regenerated with `git format-patch`.
Anything reusable (a real `qnx-ports` recipe for libuv/OpenSSL/yaml-cpp) should
eventually go upstream, not live here forever.
