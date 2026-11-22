#!/usr/bin/env python3
"""Analyse paired SEND/RECV frame logs from a weak-network run.

Log format (one CSV line per frame):
    SEND,<seq>,<dts_ms>,<pts_ms>,<size>,<key>,<wall_ms>
    RECV,<seq>,<dts_ms>,<pts_ms>,<size>,<key>,<wall_ms>,<decode_errors>

Frames are matched on dts_ms (falls back to seq). Latency is reported in two
forms:
  * raw      : recv_wall - send_wall  (contains any clock offset)
  * relative : raw - min(raw)         (offset removed; this is what the
               "bounded latency" claim is about)

Exit code is non-zero if a promise is violated (decode errors > 0).
"""
import argparse
import json
import statistics
import sys


def load(path, kind):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",")
            if len(parts) < 7 or parts[0] != kind:
                continue
            try:
                rows.append({
                    "seq": parts[1],
                    "dts": int(parts[2]),
                    "pts": int(parts[3]),
                    "size": int(parts[4]),
                    "key": int(parts[5]),
                    "wall": int(parts[6]),
                    "decode_errors": int(parts[7]) if len(parts) > 7 and parts[7] else 0,
                })
            except ValueError:
                continue
    return rows


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, int(round((p / 100.0) * (len(ordered) - 1)))))
    return ordered[k]


def slope_ms_per_min(xs, ys):
    n = len(xs)
    if n < 3:
        return 0.0
    mx = sum(xs) / n
    my = sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    if den == 0:
        return 0.0
    return (num / den) * 60000.0  # xs are in ms -> per minute


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("send_csv")
    ap.add_argument("recv_csv")
    ap.add_argument("--out", default=None, help="write summary JSON here")
    ap.add_argument("--stall-ms", type=int, default=500,
                    help="gap that counts as a stall (default 500 ms)")
    args = ap.parse_args()

    sends = load(args.send_csv, "SEND")
    recvs = load(args.recv_csv, "RECV")
    if not sends or not recvs:
        print("no usable rows", file=sys.stderr)
        return 2

    by_dts = {}
    for s in sends:
        by_dts.setdefault(s["dts"], s)

    latencies = []
    times = []
    decode_errors = 0
    matched = 0
    for r in recvs:
        decode_errors += r["decode_errors"]
        s = by_dts.get(r["dts"])
        if not s:
            continue
        matched += 1
        latencies.append(r["wall"] - s["wall"])
        times.append(r["wall"])

    if not matched:
        print("no frames matched between send and recv logs", file=sys.stderr)
        return 2

    base = min(latencies)
    rel = [x - base for x in latencies]

    recv_times = sorted(r["wall"] for r in recvs)
    stalls = []
    for a, b in zip(recv_times, recv_times[1:]):
        if b - a >= args.stall_ms:
            stalls.append(b - a)

    summary = {
        "frames_sent": len(sends),
        "frames_received": len(recvs),
        "frames_matched": matched,
        "delivery_ratio": round(len(recvs) / len(sends), 4) if sends else 0,
        "clock_offset_estimate_ms": base,
        "latency_ms": {
            "p50": percentile(rel, 50),
            "p90": percentile(rel, 90),
            "p99": percentile(rel, 99),
            "max": max(rel),
        },
        "slope_ms_per_min": round(slope_ms_per_min(times, rel), 3),
        "stalls_over_threshold": len(stalls),
        "longest_stall_ms": max(stalls) if stalls else 0,
        "decode_errors": decode_errors,
        "pass": {
            "no_artifacts": decode_errors == 0,
            "bounded_latency": abs(slope_ms_per_min(times, rel)) < 5.0,
        },
    }

    text = json.dumps(summary, indent=2)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")

    return 0 if summary["pass"]["no_artifacts"] else 1


if __name__ == "__main__":
    sys.exit(main())
