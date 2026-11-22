#!/usr/bin/env bash
# Apply symmetric-ish packet loss for a fixed duration and record the window.
#
# netem only shapes egress, so run this on BOTH endpoints (or on the two
# interfaces facing each other) to obtain loss in both directions.
#
# Usage:
#   ./scripts/netem-test.sh <loss_percent> <duration_seconds> [iface] [outdir]
#
# Example:
#   ./scripts/netem-test.sh 20 600 eth0 results/L20
#
# The script writes <outdir>/netem.json with the exact UTC window so that the
# frame logs can be trimmed to it.
set -euo pipefail

LOSS="${1:?usage: $0 <loss_percent> <duration_s> [iface] [outdir]}"
DURATION="${2:?usage: $0 <loss_percent> <duration_s> [iface] [outdir]}"
IFACE="${3:-eth0}"
OUTDIR="${4:-results/netem-${LOSS}pct-$(date +%Y%m%d-%H%M%S)}"

command -v tc >/dev/null || { echo "tc not found (iproute2)" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "run as root (tc needs CAP_NET_ADMIN)" >&2; exit 1; }

mkdir -p "$OUTDIR"

start_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
start_ms=$(date +%s%3N)

cleanup() {
  tc qdisc del dev "$IFACE" root 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> applying ${LOSS}% loss on ${IFACE} for ${DURATION}s (start ${start_utc})"
tc qdisc replace dev "$IFACE" root netem loss "${LOSS}%"
tc -s qdisc show dev "$IFACE"

sleep "$DURATION"

cleanup
trap - EXIT INT TERM

end_ms=$(date +%s%3N)
end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$OUTDIR/netem.json" <<JSON
{
  "iface": "${IFACE}",
  "loss_percent": ${LOSS},
  "duration_s": ${DURATION},
  "start_utc": "${start_utc}",
  "end_utc": "${end_utc}",
  "start_ms": ${start_ms},
  "end_ms": ${end_ms}
}
JSON

echo "==> cleared; window recorded in ${OUTDIR}/netem.json"
