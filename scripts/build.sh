#!/usr/bin/env bash
# 一键交叉编译：依赖 → OpenSSL → CMake 配置 → 构建
#
#   ./scripts/build.sh [x86_64|aarch64] [target...]
#
# 例：
#   ./scripts/build.sh x86_64 moq_transport_client
#   ./scripts/build.sh aarch64 flv2moqtransport_client
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${1:-x86_64}"
shift || true
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(moq_transport_client)

case "$ARCH" in
  x86_64|aarch64) ;;
  *) echo "usage: $0 [x86_64|aarch64] [target...]" >&2; exit 2 ;;
esac

: "${QNX_TARGET:?先 source ~/qnx800/qnxsdp-env.sh}"

echo "==== 1/4 换依赖（libuv >= 1.52）"
./scripts/fetch-deps.sh

echo "==== 2/4 编 OpenSSL 3.5（静态、含 QUIC API）"
./scripts/build-openssl.sh "$ARCH"

echo "==== 3/4 配置 CMake"
BUILD="$ROOT/build-qnx-$ARCH"
cmake -S "$ROOT/upstream" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/cmake/toolchain-qnx800-$ARCH.cmake" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}" \
  -DCMAKE_C_FLAGS="-D_QNX_SOURCE" \
  -DCMAKE_CXX_FLAGS="-D_QNX_SOURCE"

echo "==== 4/4 构建: ${TARGETS[*]}"
for t in "${TARGETS[@]}"; do
  cmake --build "$BUILD" --target "$t" -j"$(nproc 2>/dev/null || echo 4)"
done

echo
echo "产物："
find "$BUILD" -maxdepth 3 -type f \( -name '*.a' -o -name 'moq*' -o -name 'flv2moq*' \) \
  -newermt '-15 minutes' 2>/dev/null | head -20 || true
