#!/usr/bin/env bash
# Source this in a Linux shell:  . ./scripts/env.sh
# Requires QNX SDP 8.0 (there is no macOS SDP; use a Linux VM/container).

if [ -z "${QNX_SDP:-}" ]; then
  export QNX_SDP=/opt/qnx800
fi

if [ ! -f "$QNX_SDP/qnxsdp-env.sh" ]; then
  echo "env.sh: $QNX_SDP/qnxsdp-env.sh not found." >&2
  echo "        export QNX_SDP=<dir containing qnxsdp-env.sh>" >&2
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
. "$QNX_SDP/qnxsdp-env.sh"

if ! command -v qcc >/dev/null 2>&1; then
  echo "env.sh: qcc not on PATH after sourcing qnxsdp-env.sh" >&2
  return 1 2>/dev/null || exit 1
fi

echo "QNX_TARGET = $QNX_TARGET"
echo "qcc        = $(command -v qcc)"
qcc --version | head -n 1
