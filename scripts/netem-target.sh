#!/usr/bin/env bash
# Degrade ONE flow instead of the whole interface, so SSH keeps working.
#
#   ./scripts/netem-target.sh apply <loss%> <peer_ip|any> [udp_port] [iface]
#   ./scripts/netem-target.sh verify [iface] [seconds]
#   ./scripts/netem-target.sh clear [iface]
#   ./scripts/netem-target.sh show [iface]
#
# "any" (or "-") drops the destination-IP match and classifies purely by
# UDP destination port. Use it when the peer address is rewritten by NAT and the
# IP match never fires — SSH is TCP, so it still cannot be affected.
#
# Apply on BOTH endpoints: each side shapes its own egress towards the peer,
# which degrades both directions without touching ingress.
set -euo pipefail

CMD="${1:-}"
DEF_IFACE=eth0
DEF_PORT=4433

usage() {
    cat >&2 <<'USAGE'
usage:
  netem-target.sh apply <loss%> <peer_ip|any> [udp_port] [iface]
  netem-target.sh verify [iface] [seconds]
  netem-target.sh clear [iface]
  netem-target.sh show [iface]
USAGE
    exit 2
}

need_root() {
    [ "$(id -u)" -eq 0 ] || { echo "run as root (tc needs CAP_NET_ADMIN)" >&2; exit 1; }
}

# Print the packets that passed through band 3 (the netem leaf).
band3_sent() {
    tc -s qdisc show dev "$1" 2>/dev/null \
        | awk '/netem/ {getline; print $2; exit}'
}

case "$CMD" in
  apply)
    LOSS="${2:?loss percent}"
    PEER="${3:?peer ip, or \"any\"}"
    PORT="${4:-$DEF_PORT}"
    IFACE="${5:-$DEF_IFACE}"
    need_root

    RULE_DESC="udp dport ${PORT}"
    IP_MATCH=()
    if [ "$PEER" != "any" ] && [ "$PEER" != "-" ]; then
        RULE_DESC="udp -> ${PEER}:${PORT}"
        IP_MATCH=(match ip dst "${PEER}/32")
    fi

    echo "==> ${LOSS}% loss for ${RULE_DESC} on ${IFACE}"
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    # band 1:2 = default (SSH, HTTP); band 1:3 = the shaped flow
    tc qdisc add dev "$IFACE" root handle 1: prio bands 3
    tc qdisc add dev "$IFACE" parent 1:3 handle 30: netem loss "${LOSS}%"
    tc filter add dev "$IFACE" protocol ip parent 1: prio 1 u32 \
        "${IP_MATCH[@]}" \
        match ip protocol 17 0xff \
        match ip dport "${PORT}" 0xffff \
        flowid 1:3

    echo "--- qdisc ---"
    tc -s qdisc show dev "$IFACE"
    echo "--- filter ---"
    tc filter show dev "$IFACE" parent 1:
    echo
    echo "NOTE: counters are zero until traffic flows. Run the publisher, then:"
    echo "      $0 verify ${IFACE} 5"
    echo "      (if band 3 still shows 0 packets, the traffic is not matching:"
    echo "       try the \"any\" form, or check the egress interface with"
    echo "       'ip route get <peer>')"
    ;;

  verify)
    IFACE="${2:-$DEF_IFACE}"
    SECS="${3:-5}"
    before=$(band3_sent "$IFACE")
    echo "==> sampling band 3 for ${SECS}s (start: ${before:-?} pkt)"
    sleep "$SECS"
    after=$(band3_sent "$IFACE")
    echo "    end:   ${after:-?} pkt"
    if [ "${before:-0}" = "${after:-0}" ]; then
        echo "WARNING: band 3 saw no traffic in ${SECS}s." >&2
        echo "         the filter is not matching; try 'apply ... any ...'" >&2
        exit 1
    fi
    echo "OK: the shaped band is carrying traffic."
    ;;

  clear)
    IFACE="${2:-$DEF_IFACE}"
    need_root
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    echo "==> cleared ${IFACE}"
    ;;

  show)
    IFACE="${2:-$DEF_IFACE}"
    tc -s qdisc show dev "$IFACE"
    echo "--- filter ---"
    tc filter show dev "$IFACE" parent 1: 2>/dev/null || true
    ;;

  *) usage ;;
esac
