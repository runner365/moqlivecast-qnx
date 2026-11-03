#!/usr/bin/env bash
# Boot the image built by scripts/qemu-image.sh, headless, ssh forwarded to :2222.
set -euo pipefail

cd "$(dirname "$0")/.."
VM_DIR="${VM_DIR:-$PWD/.qnx-vm}"
SSH_PORT="${SSH_PORT:-2222}"

[ -f "$VM_DIR/output/qnx.ifs" ] || { echo "no image in $VM_DIR — run scripts/qemu-image.sh" >&2; exit 1; }

cd "$VM_DIR"
echo "==> booting (ssh root@localhost -p $SSH_PORT)"
mkqnximage --run=-h
