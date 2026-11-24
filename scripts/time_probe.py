#!/usr/bin/env python3
"""Estimate this machine's clock offset against a time_probe_server.

    python3 scripts/time_probe.py http://<reference>:9001/time

Uses the four-timestamp NTP formula:
    offset = ((t2 - t1) + (t3 - t4)) / 2
    error  = ((t4 - t1) - (t3 - t2)) / 2      (half the round trip)

Positive offset means this machine is AHEAD of the reference.
It repeats the exchange several times and reports the median offset, because a
single sample can be skewed by scheduling noise.
"""
import argparse
import json
import statistics
import sys
import time
import urllib.request


def now_ms():
    return int(time.time() * 1000)


def probe(url, timeout=5.0):
    t1 = now_ms()
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        payload = json.loads(resp.read().decode())
    t4 = now_ms()
    t2 = int(payload["t"])
    t3 = t2                      # the server timestamp is produced in one shot
    offset = ((t2 - t1) + (t3 - t4)) / 2.0
    delay = (t4 - t1) - (t3 - t2)
    return offset, delay


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("-n", type=int, default=9, help="samples (default 9)")
    args = ap.parse_args()

    offsets, delays = [], []
    for _ in range(args.n):
        try:
            o, d = probe(args.url)
        except Exception as exc:
            print(f"probe failed: {exc}", file=sys.stderr)
            return 2
        offsets.append(o)
        delays.append(d)
        time.sleep(0.1)

    med = statistics.median(offsets)
    print(json.dumps({
        "samples": len(offsets),
        "offset_ms_median": round(med, 2),
        "offset_ms_min": round(min(offsets), 2),
        "offset_ms_max": round(max(offsets), 2),
        "rtt_ms_median": round(statistics.median(delays), 2),
        "interpretation": (
            "reference is AHEAD of this machine by %.1f ms (this machine is BEHIND)" % med
            if med > 0 else
            "reference is BEHIND this machine by %.1f ms (this machine is AHEAD)" % (-med)
        ),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
