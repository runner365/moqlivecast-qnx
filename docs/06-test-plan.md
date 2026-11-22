# Weak-network test plan

Goal: show that MoQ over QUIC keeps **bounded latency and artifact-free video**
under packet loss where TCP-based RTMP collapses.

Three properties are claimed. Everything else is reported as a measurement, not a
promise.

| Property | Definition | Pass condition |
|---|---|---|
| **No artifacts** | Every delivered frame decodes correctly; gaps only at frame boundaries | decoder error count = 0 |
| **Bounded latency** | p99 end-to-end latency does not grow over time | linear regression slope of latency vs time ≈ 0 (< 5 ms/min) |
| **Connection survives** | the session stays up for the whole run | 10 min at 20 % loss, zero disconnects |

Reported but not promised:

| Metric | Note |
|---|---|
| frame delivery ratio | 20 % loss will drop frames; ratio is measured, not asserted |
| stall count / longest stall | a stall < 2 s is acceptable; > 5 s is a failure |
| recovery time | time to return to baseline latency after a loss burst |

---

## 1. Topology

```
  QNX target (QEMU)                Beijing ECS                 client
  ┌────────────────┐   loss y%   ┌──────────────┐  loss x%  ┌─────────────┐
  │ publisher      │ ──────────> │ moqlivecast  │ ────────> │ moq_player  │
  │ (or server +   │             │ (optional)   │           │ (records    │
  │  local source) │             └──────────────┘           │  CSV)       │
  └────────────────┘                                        └─────────────┘
```

Two variants are tested:

- **A. QNX as publisher** (port of the client SDK) — measures the QNX data path.
- **B. QNX as server** (moqlivecast + local source) — measures the server on QNX.

Variant B is the automotive scenario: the device itself serves the stream.

---

## 2. Loss injection

`netem` only affects egress, so it must be applied on **both** endpoints to get
symmetric loss.

```bash
# on each endpoint
sudo tc qdisc add dev eth0 root netem loss 20% delay 5ms
# verify
tc -s qdisc show dev eth0
# remove
sudo tc qdisc del dev eth0 root
```

Use `scripts/netem-test.sh` to automate apply → run → clear and to record the
exact windows.

Scenarios:

| id | loss | delay | duration | purpose |
|---|---|---|---|---|
| L0 | 0 % | 5 ms | 5 min | baseline |
| L5 | 5 % | 5 ms | 5 min | mild |
| L10 | 10 % | 5 ms | 5 min | moderate |
| L20 | 20 % | 5 ms | **10 min** | headline scenario |
| L30 | 30 % | 5 ms | 5 min | stress / breaking point |
| R5 | 5 % (RTMP) | 5 ms | 5 min | baseline comparison, expected to fail |

---

## 3. Instrumentation

Both sides emit one CSV line per frame. Clocks must be synchronised (chrony or
NTP); the analysis tools correct the residual offset with a minimum filter.

Sender (`publisher`):

```
SEND,<seq>,<dts_ms>,<pts_ms>,<size>,<key>,<wall_ms>
```

Receiver (`moq_player`):

```
RECV,<seq>,<dts_ms>,<pts_ms>,<size>,<key>,<wall_ms>,<decode_errors>
```

`seq` is optional; frames are matched on `dts_ms`. `wall_ms` is
`CLOCK_REALTIME` in milliseconds.

---

## 4. Analysis

```bash
python3 scripts/analyze_frames.py results/L20/send.csv results/L20/recv.csv \
    --out results/L20/summary.json
```

Produces:

- one-way latency p50 / p90 / p99 / max, and the regression slope over time
- frame delivery ratio, longest gap, number of stalls (> 500 ms)
- decoder error total (must be 0)

---

## 5. Results table (fill in)

| scenario | p50 (ms) | p99 (ms) | slope (ms/min) | delivered | longest stall (ms) | decode errors |
|---|---|---|---|---|---|---|
| L0 baseline | | | | | | |
| L5 | | | | | | |
| L10 | | | | | | |
| **L20 (10 min)** | | | | | | |
| L30 | | | | | | |
| R5 RTMP | | | | | | |

---

## 6. What is deliberately not claimed

- **Zero stalls at 20 % loss.** Losing one packet in five means frames are lost;
  the claim is that losses cost *frames*, not *latency* and not *image integrity*.
- **Lower latency than WebRTC.** WebRTC trades content for latency by design.
  MoQ keeps whole objects and lets the application choose the trade-off.
- **Throughput.** Congestion control shrinks the window under loss; that is
  expected and is not the metric of interest.
