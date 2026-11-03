#!/usr/bin/env bash
# Weak-network injection for the demo. Run this on the *Linux middlebox*, not
# on the QNX target (QNX has no tc/netem; that is the point of the measurement).
#
# Typical topology:
#   [QNX target] --eth--> [Linux box: tc netem] --eth--> [PC running moqlivecast]
#
# Usage:
#   ./scripts/netem.sh apply  20ms 5ms 2%     # delay jitter loss
#   ./scripts/netem.sh show
#   ./scripts/netem.sh clear
set -euo pipefail

IFACE="${IFACE:-eth0}"
CMD="${1:-show}"

case "$CMD" in
  apply)
    DELAY="${2:-20ms}"
    JITTER="${3:-5ms}"
    LOSS="${4:-2%}"
    echo "==> netem on $IFACE: delay $DELAY $JITTER loss $LOSS"
    tc qdisc replace dev "$IFACE" root netem delay "$DELAY" "$JITTER" loss "$LOSS"
    tc -s qdisc show dev "$IFACE"
    ;;
  show)
    tc -s qdisc show dev "$IFACE"
    ;;
  clear)
    echo "==> removing netem from $IFACE"
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 {apply [delay] [jitter] [loss] | show | clear}" >&2
    exit 2
    ;;
esac
