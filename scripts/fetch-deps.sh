#!/usr/bin/env bash
# 把上游自带的第三方库换成能编 QNX 8 的版本。
#
# 为什么需要：上游 vendored 的 libuv 1.44.3 是按 QNX 7.x 的 syspage 结构写的，
# 在 QNX 8 上编译失败（qtime_entry.nsec / syspage_entry.new_cpuinfo 不存在）。
# QNX 8 的适配在 PR #4801，v1.51.0 尚未包含，1.52.0 起才有。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

LIBUV_VERSION="${LIBUV_VERSION:-1.53.0}"
DEST="$ROOT/upstream/3rdparty/libuv"

[ -d "$ROOT/upstream" ] || { echo "upstream/ 不存在，先跑 scripts/bootstrap.sh" >&2; exit 1; }

minor_of() {
  sed -n 's/^#define UV_VERSION_MINOR[[:space:]]*\([0-9]*\).*/\1/p' "$1/include/uv/version.h" 2>/dev/null || echo 0
}

if [ -d "$DEST" ]; then
  cur=$(minor_of "$DEST")
  if [ "${cur:-0}" -ge 52 ]; then
    echo "==> libuv minor=$cur，已满足 QNX 8 要求（>=52），跳过"
    exit 0
  fi
  echo "==> libuv minor=$cur 太老，替换为 v$LIBUV_VERSION"
  mv "$DEST" "$DEST-$(minor_of "$DEST" >/dev/null 2>&1 && echo old || echo old)"
else
  echo "==> 没有 vendored libuv，下载 v$LIBUV_VERSION"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/libuv/libuv/archive/refs/tags/v${LIBUV_VERSION}.tar.gz"
echo "==> 下载 $URL"
curl -fL --retry 3 -o "$TMP/libuv.tar.gz" "$URL"
tar -xzf "$TMP/libuv.tar.gz" -C "$TMP"

SRC=$(find "$TMP" -maxdepth 1 -type d -name 'libuv-*' | head -1)
[ -n "$SRC" ] || { echo "解压后找不到源码目录" >&2; exit 1; }

mv "$SRC" "$DEST"

echo "==> 完成：libuv $(sed -n 's/^#define UV_VERSION_STRING[[:space:]]*"\(.*\)"/\1/p' "$DEST/include/uv/version.h")"
grep -n "qtime->nsec\|new_cpuinfo" "$DEST/src/unix/qnx.c" && {
  echo "警告：新版本仍含 QNX 7 的旧结构引用，需要重新评估版本" >&2
  exit 1
} || true
