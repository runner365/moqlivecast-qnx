# moqlivecast on QNX 8.0

QNX 8.0 (QNX Everywhere) port of **[moqlivecast](https://github.com/runner365/moqlivecast)** —
a from-scratch C implementation of QUIC / HTTP/3 / WebTransport carrying
MoQ Transport (`draft-ietf-moq-transport-22`).

**One line:** live video that survives a bad network *without ever starving the
control loop next to it* — the part Linux can only approximate and QNX can prove.

This repository is **not** a fork. It contains the porting layer, the QNX build
files, the patches applied on top of a pinned upstream commit, and the evidence.
Upstream source is fetched by URL — see [`scripts/bootstrap.sh`](scripts/bootstrap.sh).

---

## Why QNX

A teleoperated robot / ultrasound probe / remote vehicle needs two very
different things on one box:

| workload | requirement | what it needs from the OS |
|---|---|---|
| 1 kHz servo / safety loop | jitter < 50 µs, never preempted | priority scheduling, no unbounded blocking |
| H.264 live video over lossy links | p99 glass-to-glass < 100 ms | adaptive bitrate, pacing, loss recovery |

On a best-effort kernel the video encoder's burst can delay the control loop by
milliseconds. On QNX the control loop gets a real priority, the media pipeline
gets a bounded CPU budget (APS), and the whole thing is measurable with
`tracelogger`. That is the story this repository has to prove with numbers,
not adjectives.

---

## Architecture (target: route A — QNX as publisher)

```
 QNX 8.0 target                                      Linux / PC
┌────────────────────────────────────────┐        ┌──────────────────┐
│ servo loop 1 kHz, SCHED_FIFO prio 20   │        │                  │
│        (separate process, untouched)   │        │   moqlivecast    │
│                                        │        │     server       │
│ capture → encode → C SDK (moqlite)  ───┼── UDP ─┤  (moq-transport) ├──→ browser / ffplay
│   prio 10      prio 5    prio 3        │        │                  │
│        └── /dev/shmem zero-copy ──┘    │        └──────────────────┘
└────────────────────────────────────────┘
                  ▲ weak-network injection (netem / tc) between the two
```

The port seam is the **C SDK** (`moq_transport_client/` / `moqlite/`) — the
smallest stable surface, and the one that belongs on a device anyway.

---

## Repository layout

| Path | What it is |
|---|---|
| `cmake/toolchain-qnx800-*.cmake` | CMake toolchain files for `qcc` (aarch64 / x86_64) |
| `port/qnx/` | QNX platform layer: priorities, CPU affinity, monotonic clock, APS hooks |
| `patches/` | `git format-patch` output applied onto the pinned upstream commit |
| `scripts/` | bootstrap, build, QEMU image, QEMU run, weak-network injection |
| `apps/qnx-publisher/` | QNX-side publisher demo (test pattern first, camera later) |
| `docs/` | pitch, porting notes, benchmark methodology + results |

---

## Quick start (Linux host)

```bash
# 1. install QNX SDP 8.0 (Linux only — there is no macOS SDP)
#    https://www.qnx.com/products/everywhere/  (free non-commercial licence)
export QNX_SDP=/opt/qnx800        # directory that contains qnxsdp-env.sh

# 2. toolchain + upstream checkout at the pinned commit
./scripts/env.sh
./scripts/bootstrap.sh            # clones upstream by URL, applies patches/

# 3. cross-compile
./scripts/build.sh                # -> build-qnx-aarch64/

# 4. run it in QEMU
./scripts/qemu-image.sh           # ~5-10 min, needs ~5 GB in the image dir
./scripts/qemu-run.sh             # boots headless, ssh on :2222
./scripts/deploy.sh               # scp the binaries into the VM
```

## Evidence (fill in as the numbers land)

| scenario | p50 | p99 | control-loop jitter (max) | notes |
|---|---|---|---|---|
| LAN, 0 % loss | — | — | — | |
| 2 % loss, 20 ms RTT | — | — | — | |
| 5 % loss, 60 ms RTT, 20 ms jitter | — | — | — | |
| same, video saturated to 100 % link | — | — | — | the point of the whole project |

Method: see [`docs/03-benchmark.md`](docs/03-benchmark.md).

---

## Upstream relationship

* upstream: <https://github.com/runner365/moqlivecast>
* pinned commit: recorded at the top of [`scripts/bootstrap.sh`](scripts/bootstrap.sh)
* patch stack: [`patches/`](patches/) — regenerated with `git format-patch`
* QNX-only code never lives upstream until it is stable enough for a PR
  (planned: `tools/qnx/` + a `qnx-ports` build recipe).

## Status

Bootstrap stage. Nothing has been run on QNX yet — see the checklist in
[`docs/02-porting-notes.md`](docs/02-porting-notes.md).

## License

MIT, matching upstream.
