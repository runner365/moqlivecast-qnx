# Why QNX, and why MoQ

Two questions decide this project: **why does the transport need QNX**, and
**why does QNX need this transport**. They have different answers.

---

## Part 1 — Why the transport needs QNX

Every competing video stack can claim "low latency over a lossy network". Almost
none can answer the next question: **what happens to everything else on the
device while the video pipeline is having a bad second?**

A remote-controlled device — surgical camera, inspection arm, teleoperated
vehicle — runs two things at once:

* **Control**: a loop that must close every millisecond. Late here means
  unstable motion, or worse. A *hard* deadline.
* **Video**: a pipeline with soft deadlines. Dropping a frame is acceptable;
  *delaying the control loop is not*.

On a best-effort scheduler both compete for the same CPU with best-effort
fairness. An encoder burst or a retransmission storm easily costs the control
loop milliseconds. `nice` makes that less likely; it cannot make it impossible.

What QNX provides instead:

| mechanism | what it buys |
|---|---|
| `SCHED_FIFO` + priority inheritance | the control loop runs when it says it will |
| APS adaptive partitioning | a hard CPU budget for the media side, even against a misconfigured priority |
| POSIX message passing / `devctl` | media state queried from any process without locks or polling |
| HAM | a crashed publisher is restarted without the player noticing |
| `tracelogger` | the timeline becomes *evidence*, not a claim |

---

## Part 2 — Why QNX needs a new transport

QNX is an operating system, not a media protocol. It ships the primitives
(io-sock, QNX Screen, QNX Sound, the Hypervisor) and ports of existing stacks,
and integrators pick the protocol. The practical options today:

| option | transport | strength | limitation for device-to-cloud media |
|---|---|---|---|
| **RTSP / RTP** | UDP (or TCP interleaved) | universal, ONVIF ecosystem | no congestion control; loss is invisible to the sender; TCP interleaving inherits head-of-line blocking |
| **WebRTC** | SRTP over UDP | excellent NAT traversal, browser-native | signalling (SDP/ICE/TURN) is heavy; it *deliberately* sacrifices content — artefacts and PLC-degraded audio; an SFU is stateful per peer |
| **AVTP / TSN** | Ethernet L2 | deterministic, ideal in-vehicle | requires a TSN-capable switch and a single administrative domain — not usable across a WAN |
| **SOME/IP** | Ethernet | standard for control signals | designed for RPC/events, not for media frames |
| **RTMP** | TCP | trivial ingest | a single loss collapses the connection; unusable on a lossy link |
| **MoQ (this work)** | QUIC | per-object reliability, per-stream priority, congestion control, connection migration | newer protocol, browser support via WebTransport only |

`qnx-ports` already carries `webrtc`, `vlc`, `libcamera`, `nghttp2` and `curl`;
there is **no Media-over-QUIC option**. That is the gap this port fills.

### What MoQ actually buys — stated carefully

MoQ does **not** promise lower latency than WebRTC. It changes *what you are
allowed to sacrifice*:

| under packet loss | WebRTC | MoQ (default) | MoQ (with a drop policy) |
|---|---|---|---|
| behaviour | skip packets | wait for retransmission | drop the whole object |
| image | artefacts (partial frame) | intact | intact or a skipped frame, never partial |
| latency | stable | +1 RTT per loss event | stable |

Because objects travel on independent QUIC streams, a lost packet stalls only
that object, not the following ones; and because the unit of loss is a whole
object, the receiver never decodes half a frame. The application chooses between
"wait" and "skip" — WebRTC hard-codes the second one.

That distinction matters when the consumer is not a human eye but an ASR
pipeline, a detector, or a remote operator making a decision: a cleanly skipped
frame is recoverable, a corrupted one is not.

---

## What this submission claims

Measured on the three-party topology in [`04-test-plan.md`](04-test-plan.md)
(QNX device in Hong Kong → server in Beijing → player):

| claim | measurement |
|---|---|
| no artefacts under loss | decoder error count = 0 at 20 % loss |
| latency does not accumulate | latency delta ≈ 0 over a 10-minute run |
| the session survives | no disconnect at 20 % loss |
| the device-side cost is small | uplink latency at 0 % loss is dominated by the WAN, not by QNX |

The control-loop priority experiment (video saturating the link while a 1 kHz
loop keeps its deadline) is the next step, and the repository already contains
the platform layer it needs in `port/qnx/`.
