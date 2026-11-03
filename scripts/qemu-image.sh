#!/usr/bin/env bash
# Build a bootable QNX 8.0 QEMU image with ssh enabled.
# Takes 5-10 min the first time and needs ~5 GB free in VM_DIR.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${ARCH:-aarch64}"          # aarch64 | x86_64
VM_DIR="${VM_DIR:-$ROOT/.qnx-vm}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"

if ! command -v mkqnximage >/dev/null 2>&1; then
  echo "mkqnximage not on PATH — source \$QNX_SDP/qnxsdp-env.sh first" >&2
  exit 1
fi
[ -f "$SSH_KEY" ] || { echo "no ssh public key at $SSH_KEY (override with SSH_KEY=)" >&2; exit 1; }

mkdir -p "$VM_DIR"
cd "$VM_DIR"

echo "==> mkqnximage: arch=$ARCH dir=$VM_DIR"
mkqnximage \
  --type=qemu \
  --arch="$ARCH" \
  --ssh-ident="$SSH_KEY" \
  --data-size=4096 \
  --data-inodes=40000 \
  --noprompt

echo "==> image ready in $VM_DIR"
echo "    boot it with: ./scripts/qemu-run.sh"
