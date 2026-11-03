# Benchmark methodology

The point of the project is a number, so the measurement has to survive
scrutiny. Three rules: **same clock, single artifact, published raw data.**

## 1. Clock and timestamps

* Sender stamps every frame with `moq_qnx_mono_ns()` (monotonic, ns).
* Receiver logs `now - ts` per frame to a CSV.
* One clock domain. If sender and receiver are different machines, sync with
  PTP/`ntpd` **and** report the residual offset — or use the camera method below.

## 2. Glass-to-glass (the honest number)

Camera-side method, no clock sync needed:

1. A monitor displays a millisecond stopwatch (or a QR code encoding the time).
2. The QNX device's camera films the monitor.
3. The player window shows the received frame next to a live copy of the
   stopwatch.
4. Screenshot both, read the delta. Repeat 30×, report p50/p99.

Frame-level timestamps are faster to collect and fine for regression testing;
glass-to-glass is what goes in the demo video.

## 3. Network conditions

Injected by `scripts/netem.sh` on a Linux middlebox:

| profile | delay | jitter | loss |
|---|---|---|---|
| LAN | — | — | 0 % |
| good 4G | 20 ms | 5 ms | 0.5 % |
| bad 4G | 60 ms | 20 ms | 2 % |
| hostile | 80 ms | 30 ms | 5 % |
| hostile + saturation | 80 ms | 30 ms | 5 % + 100 % link utilization |

The last row is the one that matters: it is where a best-effort scheduler
starts hurting the control loop.

## 4. Control-loop jitter

A 1 kHz thread:

```c
moq_qnx_set_realtime(MOQ_QNX_PRIO_SERVO);
next = moq_qnx_mono_ns();
for (;;) {
    next += 1000000;                    /* 1 ms */
    while (moq_qnx_mono_ns() < next) { /* spin, like a real servo */ }
    uint64_t actual = moq_qnx_mono_ns();
    record(actual - next);              /* lateness, ns */
}
```

Report max and p99.9 lateness over 60 s. Reference run: same binary on Linux
with `SCHED_FIFO` + `isolcpus`, to show the difference is scheduling, not luck.

## 5. Results

| scenario | video p50 | video p99 | control max jitter | control p99.9 | dropped frames |
|---|---|---|---|---|---|
| LAN | | | | | |
| 2 % / 60 ms | | | | | |
| 5 % / 80 ms | | | | | |
| 5 % / 80 ms + saturation | | | | | |

**Acceptance thresholds** (revise once, then freeze):

* video p99 glass-to-glass **< 100 ms** at ≤ 5 % loss;
* control max jitter **< 50 µs** while video saturates the link;
* zero control-loop deadline misses in a 60 s run (publish the raw log).

## 6. Artifacts to publish

* `results/*.csv` — raw per-frame latency and per-tick jitter,
* `results/trace.png` — `tracelogger` timeline showing the control thread,
* `results/plot.py` — regenerates every figure from the CSVs,
* a 60 s screen recording (`docs/demo.mp4`) of the stopwatch test under netem.
