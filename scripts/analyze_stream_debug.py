#!/usr/bin/env python3
"""Pair moqlivecast [stream-debug] lines with flv2moqtransport_client
[client-debug] lines and report one-way latency statistics.

Both sides print, per video frame:
    [client-debug] dts=<ms> wall_ms=<unix_ms> app=<a> stream=<s> key=<0|1> size=<n>
    [stream-debug] dts=<ms> wall_ms=<unix_ms> app=<a> stream=<s> codec=<C> key=<0|1> size=<n>

Frames are matched on (app, stream, dts). If a dts repeats (looped input) the
entries are consumed in arrival order, and the duplicate count is reported so the
reader knows the matching was ambiguous.

Latency is `server_wall - client_wall`. If the two hosts are not perfectly
synchronised, subtract the known clock offset with --offset-ms (server ahead of
client => positive). Without an offset the script reports the minimum observed
latency as an upper bound on the offset.

Exit code is 1 when duplicate dts were seen (matching is ambiguous).
"""
import argparse
import json
import re
import sys
from collections import deque

PAT = re.compile(
    r"\[(?P<side>client-debug|stream-debug)\]\s+"
    r"dts=(?P<dts>-?\d+)\s+"
    r"wall_ms=(?P<wall>\d+)\s+"
    r"app=(?P<app>\S+)\s+"
    r"stream=(?P<stream>\S+)"
)


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = PAT.search(line)
            if not m:
                continue
            rows.append({
                "side": m.group("side"),
                "dts": int(m.group("dts")),
                "wall": int(m.group("wall")),
                "app": m.group("app"),
                "stream": m.group("stream"),
            })
    return rows


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    i = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[i]


def slope(xs, ys):
    n = len(xs)
    if n < 3:
        return 0.0
    mx = sum(xs) / n
    my = sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    return (num / den) * 60000.0 if den else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("client_log")
    ap.add_argument("server_log")
    ap.add_argument("--offset-ms", type=float, default=0.0,
                    help="server_clock - client_clock, in ms")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    client = load(args.client_log)
    server = load(args.server_log)
    if not client or not server:
        print("no usable log lines", file=sys.stderr)
        return 2

    pending = {}
    for c in client:
        pending.setdefault((c["app"], c["stream"], c["dts"]), deque()).append(c["wall"])

    lat, times = [], []
    duplicates = 0
    matched = 0
    for s in server:
        key = (s["app"], s["stream"], s["dts"])
        q = pending.get(key)
        if not q:
            continue
        client_wall = q.popleft()
        if q:
            duplicates += 1
        lat.append(s["wall"] - client_wall - args.offset_ms)
        times.append(s["wall"])
        matched += 1

    if not lat:
        print("no frames matched (check app/stream names)", file=sys.stderr)
        return 2

    base = min(lat)
    rel = [x - base for x in lat]

    summary = {
        "client_frames_logged": len(client),
        "server_frames_logged": len(server),
        "frames_matched": matched,
        "delivery_ratio": round(len(server) / len(client), 4),
        "latency_ms": {
            "p50": pct(rel, 50), "p90": pct(rel, 90),
            "p99": pct(rel, 99), "max": max(rel),
        },
        "min_latency_ms_upper_bound_of_clock_offset": base,
        "slope_ms_per_min": round(slope(times, rel), 3),
        "duplicate_dts": duplicates,
        "bounded_latency": abs(slope(times, rel)) < 5.0,
    }

    text = json.dumps(summary, indent=2)
    print(text)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(text + "\n")
    return 1 if duplicates else 0


if __name__ == "__main__":
    sys.exit(main())
