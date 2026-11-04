# Devpost 提交材料（持续更新）

> 赛事：QNX Global Hackathon（<https://qnx.devpost.com/>）
> 截止：**2026-12-15 14:00 ET = 北京时间 12-16 03:00**；建议 **12-13 前**点 Submit。
> 状态标记：✅ 已定稿 · 🔄 有草稿待补 · ⬜ 未开始

---

## 1. 表单字段与当前内容

| 字段 | 内容 | 状态 |
|---|---|---|
| Project name | `PulseCast`（若改名，Devpost / README / 视频标题三处同步） | 🔄 |
| Elevator pitch | `Real-time Media over QUIC (MoQ) video for QNX 8.0 that survives bad networks without ever delaying a hard real-time control loop.` | ✅ |
| Submission category | `Robotics & Medical` | ✅ |
| Code repository URL | `https://github.com/runner365/moqlivecast-qnx` | ✅ |
| Try it out | `https://github.com/runner365/moqlivecast-qnx` | ✅ |
| Demo video URL | YouTube，public，<3 分钟 | ⬜ W5 |
| Image gallery | 6–8 张，3:2，≤5 MB | ⬜ W2–W4 边做边截 |
| Built with | 见下 | ✅ |
| Codelab URL（专项奖） | 待定，有余力写 | ⬜ |

### Built with（14 个，按顺序输入）

```
QNX
QNX 8.0
C
C++
QUIC
HTTP/3
WebTransport
MoQ
Media over QUIC
libuv
OpenSSL
CMake
QEMU
Raspberry Pi 5
```

原则：只填真用到的；不填满（10–15 个最佳）。

---

## 2. Project Story（草稿，`[TBD]` 待 W4 填数）

```markdown
# PulseCast — real-time Media over QUIC video for QNX 8.0

## Inspiration

A teleoperated surgical camera, a remote inspection arm, a driverless shuttle — they all
run two workloads on one computer: a control loop with *hard* deadlines, and a video
pipeline with *soft* ones. Drop a frame and nothing bad happens. Delay the control loop
by two milliseconds and the machine misbehaves.

On a best-effort kernel those two workloads compete with each other. An encoder burst, a
retransmission storm, a garbage collection pause — any of them can push the control loop
past its deadline. You can raise priorities, but you cannot *prove* anything.

QNX can prove it. That gap is what this project is about: not "video works on QNX", but
"video works on QNX *and the control loop never notices*".

## What it does

PulseCast turns a QNX 8.0 device into a real-time video node:

- captures frames (test pattern or recorded source), timestamps them, and publishes them
  as **MoQ (Media over QUIC)** objects over a single QUIC connection;
- keeps the media pipeline inside a bounded CPU budget, with the control loop above it in
  priority;
- reports per-session latency, loss and bitrate through a `/dev/moq` resource manager;
- recovers from a publisher crash without the player losing the stream.

Under 5% packet loss and a saturated uplink, video degrades in quality — the control
channel keeps its RTT.

## How I built it

The upstream project is [moqlivecast](https://github.com/runner365/moqlivecast): a
from-scratch C implementation of QUIC, HTTP/3, WebTransport and MoQ Transport
(draft-ietf-moq-transport-22), no third-party QUIC library. It runs on Linux. Porting it
whole would have been the obvious move, and the wrong one.

### 1. The port seam is the C SDK, not the server

The device-side surface is the C SDK (`moq_transport_client/`), the smallest piece that
still exercises the hard parts: sockets, timers, TLS, congestion control, pacing. That cut
the port from "the whole tree" to "one library and its dependencies".

The QNX-specific code lives in `port/qnx/` and never leaks into upstream files: scheduling
priority, CPU affinity, a monotonic clock, and the ability layer needed to raise priority
on QNX. It compiles on Linux too (stubbed), so it can be unit-tested on the host before a
target exists.

### 2. Rebuild the media path around QNX primitives

This is the part that makes it a QNX project rather than a port:

| mechanism | what it buys |
|---|---|
| `SCHED_FIFO` priority map (servo > capture > encode > net > stats) | the control loop runs when it says it will |
| APS partition bounding the media pipeline | a burst cannot steal the control loop's slack, even with a wrong priority |
| `/dev/moq` resource manager + `devctl` | any process can query session state without locks or polling |
| HAM-managed publisher | a crashed encoder restarts without the player noticing |
| `tracelogger` | the timeline is evidence, not a claim |

### 3. Measure, then claim

A 1 kHz control thread and the video path run side by side while a Linux middlebox injects
delay, jitter and loss with `tc netem`. Numbers below are from the QNX target, with a
Linux baseline for comparison.

| scenario | video p50 | video p99 | control max jitter | frames dropped |
|---|---|---|---|---|
| LAN, 0% loss | [TBD] | [TBD] | [TBD] | [TBD] |
| 2% loss, 60 ms RTT | [TBD] | [TBD] | [TBD] | [TBD] |
| 5% loss, 80 ms RTT | [TBD] | [TBD] | [TBD] | [TBD] |
| 5% loss + uplink saturated | [TBD] | [TBD] | [TBD] | [TBD] |

## How this uses QNX (for reviewers)

- `port/qnx/qnx_platform.c` — `pthread_setschedparam` priority policy, `ThreadCtl`
  runmask pinning, `CLOCK_MONOTONIC` timing
- `port/qnx/moq_rm.c` — `/dev/moq` resource manager, `devctl` handlers for session stats
- `scripts/qnx-aps.sh` — APS partition setup for the media pipeline
- `cmake/toolchain-qnx800-*.cmake` — `qcc` toolchain files for aarch64 and x86_64
- `patches/` — the porting patches applied to a pinned upstream commit
- `docs/03-benchmark.md` — measurement method and raw data

## Challenges

**The host toolchain does not exist on ARM or macOS.** QNX SDP is an x86_64 Linux/Windows
product, so development moved to an x86_64 Linux host while the editor and player stayed on
the Mac.

**io-sock is not Linux.** `sendmmsg`, `signalfd`, `SO_REUSEPORT`, `timerfd` — each one is a
small assumption that has to be checked, replaced or worked around. The list is in
`docs/02-porting-notes.md` and it is longer than expected.

**Emulation is not a measurement.** QEMU is fine for "does it boot", useless for "does the
control loop meet its deadline" — the host scheduler pollutes the numbers. Real-time
evidence has to come from real hardware.

## What I learned

[W4 之后补：一句真话。候选方向——"实时"的关键是优先级继承而不是绝对速度；换掉一个
`sendmmsg` 如何改变 pacing 行为；移植工作量的大头在构建系统而不是代码。]

## What's next

- camera input on the target (the recorded-source path stays as the reproducible default)
- stream-level prioritization: give the control channel a higher QUIC stream priority than
  video, so congestion degrades video first
- multi-track metadata (detections, ROI) on the same connection

## Links

- Submission repository: https://github.com/runner365/moqlivecast-qnx
- Upstream project: https://github.com/runner365/moqlivecast
```

---

## 3. Image Gallery 计划（3:2，≤5 MB，最多 15 张）

| # | 内容 | 怎么来 | 何时 |
|---|---|---|---|
| 1 | 主视觉：RPi5 + 播放画面（或延迟曲线大图） | 手机拍后裁 3:2 | W4 |
| 2 | 架构图（QNX 三进程 + 优先级 + MCU） | Excalidraw / draw.io | W2 |
| 3 | `pidin` 显示线程优先级 | 目标机截图 | W3 |
| 4 | `/dev/moq` 的 `devctl` 输出 | 目标机截图 | W3 |
| 5 | 延迟曲线（p50/p99，四种 netem 场景） | 由 `results/*.csv` 画 | W4 |
| 6 | 控制 jitter 直方图（QNX vs Linux） | 同上 | W4 |
| 7 | `tracelogger` 时间线 | QNX trace 工具 | W4 |
| 8 | 浏览器播放端画面 | Mac 截屏 | W2 |

要点：第 1 张决定别人要不要往下看，别放代码截图；统一裁到 1200×800。

## 4. Demo Video 结构（<3 分钟，YouTube public）

| 时间 | 内容 |
|---|---|
| 0:00–0:20 | 问题：控制回路 + 视频抢 CPU，Linux 上的抖动 |
| 0:20–0:50 | 方案：PulseCast 架构一页图 |
| 0:50–1:40 | 演示：netem 5% 丢包，视频降质不断流，控制 jitter 平稳 |
| 1:40–2:20 | QNX 特写：`pidin` 优先级、`/dev/moq` 查询、HAM 重启 |
| 2:20–2:50 | 数据：p50/p99 表格 + Linux 对照 |
| 2:50–3:00 | 收尾：仓库地址 + 上游链接 |

限制：必须 public（不能 unlisted）；不得含第三方商标或未授权音乐。

---

## 5. 待办

- [ ] W2：画架构图（Gallery #2）
- [ ] W3：截 `pidin` / `devctl` 输出（Gallery #3、#4）
- [ ] W4：跑 netem 矩阵，填 Story 数据表，出延迟/jitter 图（Gallery #5、#6、#7）
- [ ] W5：拍视频、上传 YouTube（public）
- [ ] W5：`What I learned` 补一句真话
- [ ] 12-13：填完所有字段，点 **Submit project**
