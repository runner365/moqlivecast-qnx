# Weak-network test plan

Goal: quantify what MoQ over QUIC does under packet loss, on a realistic
three-party topology, without relying on "it looked smooth".

## 1. Topology

```
 (1) QNX target            (2) moqlivecast            (3) player
     Hong Kong ECS             Beijing ECS               macOS, Beijing
  ┌──────────────┐   WAN   ┌──────────────────┐  LAN  ┌──────────────┐
  │ publisher    │────────>│ receive → GOP    │──────>│ moq_player   │
  │ (QNX/QEMU)   │  loss%  │ cache → serve    │ loss% │ (records CSV)│
  └──────────────┘         └──────────────────┘       └──────────────┘
     t0: send                 t1: arrive                 t3: render
                              t2: re-send
```

Four timestamps give a latency budget:

| Segment | Formula | Measured at | Clock sync needed |
|---|---|---|---|
| **A** uplink | `t1 − t0` | HK ↔ BJ | yes |
| **B** server processing | `t2 − t1` | inside one process | **no** |
| **C** downlink | `t3 − t2` | BJ ↔ BJ (LAN) | yes, small error |
| **Total** | `t3 − t0` | end to end | yes (cross-checked visually) |

Segment B is measured against a single clock, so it carries no synchronisation
error at all. That is the number that answers "what does the QNX port cost".

## 2. Clock discipline

All three machines run `chrony` against the same NTP pool.

```bash
chronyc tracking | grep -E "System time|Last offset"
```

The measured offset is reported next to the results, so the reader can judge the
error instead of trusting the numbers blindly. Typical offset on this setup is a
few milliseconds, against latencies of 100 ms+.

Total latency is **cross-checked** with a clock-free method (section 6). If the
two independent methods agree within 15 ms, the measurement is credible.

## 3. Loss injection

`netem` only shapes egress, so apply it at both ends of the hop under test.

```bash
# Hong Kong ECS (uplink direction)
sudo tc qdisc add dev eth0 root netem loss 20%
# Beijing ECS (uplink direction of the reverse path + downlink)
sudo tc qdisc add dev eth0 root netem loss 20%
```

Use `scripts/netem-test.sh` to bracket the window and record timestamps.

| id | uplink loss | downlink loss | duration | purpose |
|---|---|---|---|---|
| L0 | 0 % | 0 % | 5 min | baseline |
| L5 | 5 % | 5 % | 5 min | mild |
| L10 | 10 % | 10 % | 5 min | moderate |
| **L20** | **20 %** | **20 %** | **10 min** | headline |
| L30 | 30 % | 30 % | 5 min | breaking point |
| R5 | 5 % (RTMP end to end) | 5 % | 5 min | TCP baseline, expected to fail |

## 4. Instrumentation

Both sides print one line per **video** frame, gated by an environment variable so
the logging can be switched off outside test runs.

Publisher (`flv2moqtransport_client`, `MOQ_CLIENT_DEBUG=1`), right after FLV demux:

```
[client-debug] dts=<ms> wall_ms=<unix_ms> app=<a> stream=<s> key=<0|1> size=<n>
```

Server (`moqlivecast`, `MOQ_STREAM_DEBUG=1`), in the MoQ receive path after the
frame is depacketised:

```
[stream-debug] dts=<ms> wall_ms=<unix_ms> app=<a> stream=<s> codec=<H264|H265> key=<0|1> size=<n>
```

Notes:

- `wall_ms` is `CLOCK_REALTIME` captured **at the call site**, not by the logging
  macro, so an asynchronous logger cannot shift the timestamp.
- Frames are matched on `(app, stream, dts)`. The publisher has no sequence number,
  so **looped input makes dts repeat**; do not loop the source during a run, or
  treat duplicate matches as ambiguous (the analyser reports them).
- The client timestamp is taken at demux, so the measured value includes the
  client's own queueing. This is stated rather than hidden.

## 5. Promises and metrics

Promised (all testable):

| Promise | Definition | Pass condition |
|---|---|---|
| **No artifacts** | every delivered frame decodes correctly | `decode_errors == 0` |
| **Latency does not accumulate** | delta of one-way latency stays near zero | mean delta ≈ 0, p99 delta < 50 ms |
| **Connection survives** | session stays up for the whole run | 10 min at 20 % loss, zero disconnects |

Reported, not promised:

| Metric | Why it is not promised |
|---|---|
| frame delivery ratio | 20 % loss *will* drop frames |
| stall count / longest stall | depends on GOP length and player buffering |
| recovery time | depends on the encoder's next keyframe interval |

## 6. Clock-free cross-check (visual)

The publisher burns `CLOCK_REALTIME` into each frame. The player window shows the
decoded frame next to a live clock on the same page. A screenshot then contains
both values, so the total latency can be read directly with no clock sync at all.

This is used to validate the NTP-based numbers, and it is the shot used in the
demo video.

## 7. Analysis

```bash
python3 scripts/analyze_stream_debug.py client.log server.log \
    --offset-ms <server_clock_minus_client_clock> \
    --out results/L20/summary.json
```

The analyser reports p50/p90/p99/max, the regression slope (does latency grow?),
delivery ratio, and the number of ambiguous (duplicate-dts) matches. Without
`--offset-ms` it prints the minimum observed latency as an upper bound on the
clock offset, which is usually enough to show that the offset is far below the
latencies being measured.

## 8. Results table (fill in)

| scenario | A up p50/p99 | B server p50/p99 | C down p50/p99 | total p99 | slope | delivered | longest stall | decode errors |
|---|---|---|---|---|---|---|---|---|
| L0 | | | | | | | | |
| L5 | | | | | | | | |
| L10 | | | | | | | | |
| **L20** | | | | | | | | |
| L30 | | | | | | | | |
| R5 RTMP | | | | | | | | |

## 9. What is deliberately not claimed

- **Zero stalls at 20 % loss** — losing one packet in five loses frames; the claim
  is that losses cost frames, not latency and not image integrity.
- **Lower latency than WebRTC** — WebRTC trades content for latency by design;
  MoQ keeps whole objects and lets the application choose the trade-off.
- **"Smooth playback"** — replaced by decode errors, stalls and delivery ratio,
  because "smooth" cannot be verified by a reviewer.
