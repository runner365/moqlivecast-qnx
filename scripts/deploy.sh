#!/usr/bin/env bash
# Copy built artifacts + demo config into the running QEMU target.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${ARCH:-aarch64}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_HOST="${SSH_HOST:-root@localhost}"
BUILD="${BUILD:-$ROOT/build-qnx-$ARCH}"
DEST="${DEST:-/data/moq}"

[ -d "$BUILD" ] || { echo "no build dir $BUILD — run scripts/build.sh" >&2; exit 1; }

echo "==> mkdir $DEST on target"
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no "$SSH_HOST" "mkdir -p $DEST"

echo "==> scp executables (and any staged libs)"
mapfile -t files < <(find "$BUILD" -maxdepth 3 -type f \
  \( -perm -u+x -o -name '*.so*' \) ! -name '*.cmake' | sort)

if [ ${#files[@]} -eq 0 ]; then
  echo "nothing to copy yet — the port has not produced binaries" >&2
  exit 1
fi

for f in "${files[@]}"; do
  echo "    $f"
done
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "${files[@]}" "$SSH_HOST:$DEST/"

echo "==> done: $DEST (${#files[@]} files)"
