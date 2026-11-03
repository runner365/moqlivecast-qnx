#!/usr/bin/env bash
# Cross-compile the QNX target. Assumes scripts/bootstrap.sh has run and
# qnxsdp-env.sh has been sourced (scripts/env.sh).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${1:-aarch64}"
case "$ARCH" in
  aarch64|x86_64) ;;
  *) echo "usage: $0 [aarch64|x86_64]" >&2; exit 2 ;;
esac

: "${QNX_TARGET:?source scripts/env.sh first (QNX_TARGET is unset)}"
[ -d "$ROOT/upstream" ] || { echo "run scripts/bootstrap.sh first" >&2; exit 1; }

BUILD="$ROOT/build-qnx-$ARCH"
TOOLCHAIN="$ROOT/cmake/toolchain-qnx800-$ARCH.cmake"

echo "==> configure ($ARCH)"
cmake -S "$ROOT/upstream" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}" \
  -DCMAKE_INSTALL_PREFIX="$BUILD/stage"

echo "==> build"
cmake --build "$BUILD" -j"$(nproc 2>/dev/null || echo 4)"

echo "==> artifacts"
find "$BUILD" -maxdepth 3 -type f -perm -u+x -name 'moq*' -o -maxdepth 3 -type f -name '*.a' 2>/dev/null | head -n 20
