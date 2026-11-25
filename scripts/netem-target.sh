#!/usr/bin/env bash
# Degrade ONE flow (destination IP + UDP port) instead of the whole interface,
# so SSH and management traffic keep working while the media path suffers.
#
#   ./scripts/netem-target.sh apply <loss%> <peer_ip> [udp_port] [iface]
#   ./scripts/netem-target.sh clear [iface]
#   ./scripts/netem-target.sh show  [iface]
#
# Run it on BOTH endpoints: each side shapes its egress towards the peer, which
# gives loss in both directions without touching ingress.
set -euo pipefail

CMD="${1:-}"
DEF_IFACE=eth0

usage() {
    echo "usage: $0 {apply <loss%> <peer_ip> [udp_port] [iface] | clear [iface] | show [iface]}" >&2
    exit 2
}

need_root() {
    [ "$(id -u)" -eq 0 ] || { echo "run as root (tc needs CAP_NET_ADMIN)" >&2; exit 1; }
}

case "$CMD" in
  apply)
    LOSS="${2:?loss percent}"; PEER="${3:?peer ip}"; PORT="${4:-4433}"; IFACE="${5:-$DEF_IFACE}"
    need_root
    echo "==> ${LOSS}% loss for udp -> ${PEER}:${PORT} on ${IFACE}"
    # start from a clean root qdisc, then three priority bands:
    #   band 1:2 = everything else (SSH, HTTP) - untouched
    #   band 1:3 = the media flow, with netem
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc add dev "$IFACE" root handle 1: prio bands 3
    tc qdisc add dev "$IFACE" parent 1:3 handle 30: netem loss "${LOSS}%"
    tc filter add dev "$IFACE" protocol ip parent 1: prio 1 u32 \
        match ip dst "${PEER}/32" \
        match ip protocol 17 0xff \
        match ip dport "${PORT}" 0xffff \
        flowid 1:3
    echo "--- qdisc ---"; tc -s qdisc show dev "$IFACE"
    echo "--- filters ---"; tc filter show dev "$IFACE" parent 1:
    ;;
  clear)
    IFACE="${2:-$DEF_IFACE}"; need_root
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    echo "==> cleared ${IFACE}"
    ;;
  show)
    IFACE="${2:-$DEF_IFACE}"
    tc -s qdisc show dev "$IFACE"
    echo "--- filters ---"; tc filter show dev "$IFACE" parent 1: 2>/dev/null || true
    ;;
  *) usage ;;
esac
