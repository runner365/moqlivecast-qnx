# Why this needs QNX (the 60-second version)

Every competing video stack can say "low latency over a lossy network". Almost
none can answer the next question: **what happens to everything else on the
device while the video pipeline is having a bad second?**

That question is the whole project.

## The two workloads

A remote-controlled device — surgical camera, inspection arm, teleoperated
vehicle — runs two things at once:

* **Control.** A loop that must close every millisecond. Late here means
  unstable motion, or worse. This is a *hard* deadline.
* **Video.** A pipeline with soft deadlines: dropping a frame is acceptable,
  *delaying the control loop is not*.

On a best-effort scheduler both compete for the same CPU with best-effort
fairness. A 1080p encoder burst, a GC pause, or a burst of retransmissions
easily costs the control loop milliseconds. You cannot fix that with `nice`;
you can only make it *less likely*.

## What QNX gives instead

| mechanism | what it buys |
|---|---|
| `SCHED_FIFO` + priority inheritance | the control loop runs when it says it will |
| APS adaptive partitioning | a hard CPU budget for the media side, even against a misconfigured priority |
| POSIX message passing / `devctl` | media state queried from any process without locks or polling |
| HAM | a crashed publisher is restarted without the player noticing |
| `tracelogger` | the timeline is *evidence*, not a claim |

The last row matters for judging: a hackathon entry can assert "real-time", or
it can show a trace with the control thread never missing a deadline while the
video path saturates the link. This repository exists to produce the second
kind.

## What MoQ adds on top

MoQ (Media over QUIC) carries media as objects on QUIC streams instead of as an
RTP session on top of a lossy transport. That means:

* one connection, no head-of-line blocking between tracks,
* congestion control that is per-connection but *schedulable* per stream,
* and — the part this project leans on — the ability to give the control
  channel a higher stream priority than the video, so that under loss the
  video degrades first and the control channel keeps its RTT.

That last property is what turns "a transport port" into a real-time design.

## The claim this repo has to defend

> With the link at 5 % loss and 60 ms RTT, and video saturating the uplink:
> glass-to-glass p99 stays under 100 ms, and the 1 kHz control loop's maximum
> jitter stays under 50 µs on QNX — while the same setup on Linux shows
> millisecond-scale control jitter.

Numbers, a trace, and a reproducible harness. See `docs/03-benchmark.md`.
