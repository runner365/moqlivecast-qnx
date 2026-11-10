#!/usr/bin/env bash
# 为 QNX 交叉编译 OpenSSL 3.5.x（必须带 QUIC API）。
#
# 为什么必须自己编：
#   - 代码用了 SSL_set_quic_tls_cbs，这是 OpenSSL 3.5 才有的 QUIC API；
#     QNX SDP 自带的是 3.0.x，运行时 undefined symbol。
# 为什么用静态库：
#   - 系统里已有 libssl.so.3（3.0.x），动态链接会 SONAME 冲突。
# 为什么要包装脚本：
#   - qcc 不认 -MF，见 scripts/qcc-nodep。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64)
    QCC_VARIANT=gcc_ntox86_64; AR_TOOL=ntox86_64-ar
    RANLIB_TOOL=ntox86_64-ranlib; NM_TOOL=ntox86_64-nm
    OS_TARGET=linux-x86_64 ;;
  aarch64)
    QCC_VARIANT=gcc_ntoaarch64le; AR_TOOL=ntoaarch64-ar
    RANLIB_TOOL=ntoaarch64-ranlib; NM_TOOL=ntoaarch64-nm
    OS_TARGET=linux-aarch64 ;;
  *) echo "usage: $0 [x86_64|aarch64]" >&2; exit 2 ;;
esac

: "${QNX_HOST:?先 source ~/qnx800/qnxsdp-env.sh}"
[ -d "$ROOT/upstream" ] || { echo "upstream/ 不存在，先跑 scripts/bootstrap.sh" >&2; exit 1; }

SRC="$ROOT/upstream/3rdparty/openssl-3.5.8"
BUILD="$ROOT/build-qnx-$ARCH"
INSTALL="$BUILD/openssl_install"

[ -d "$SRC" ] || { echo "找不到 $SRC" >&2; exit 1; }

# 已经编好且是 QNX 版就跳过
if [ -f "$INSTALL/lib/libssl.a" ]; then
  bad=$("$QNX_HOST/usr/bin/$NM_TOOL" "$INSTALL/lib/libcrypto.a" 2>/dev/null \
        | grep -c "__errno_location" || true)
  if [ "${bad:-1}" -eq 0 ] && \
     "$QNX_HOST/usr/bin/$NM_TOOL" "$INSTALL/lib/libssl.a" 2>/dev/null \
        | grep -q SSL_set_quic_tls_cbs; then
    echo "==> $ARCH 的 OpenSSL 已是 QNX 版，跳过"
    exit 0
  fi
  echo "==> 现有 OpenSSL 是宿主版，重编"
fi

WRAP="$ROOT/scripts/qcc-nodep"
chmod +x "$WRAP"

cd "$SRC"
echo "==> Configure ($OS_TARGET, $QCC_VARIANT)"
rm -f Makefile configdata.pm
./Configure no-shared no-tests no-asm no-async no-afalgeng \
  --prefix="$ROOT/qnx-openssl/$ARCH" \
  --openssldir=/data/ssl \
  CC="$WRAP -V$QCC_VARIANT" \
  AR="$AR_TOOL" RANLIB="$RANLIB_TOOL" \
  "$OS_TARGET"

echo "==> 编译（只编库，跳过 apps/tests）"
make -j"$(nproc 2>/dev/null || echo 4)" build_libs

echo "==> 校验产物"
bad=$("$QNX_HOST/usr/bin/$NM_TOOL" libcrypto.a 2>/dev/null | grep -c "__errno_location" || true)
if [ "${bad:-1}" -ne 0 ]; then
  echo "错误：libcrypto.a 仍含 glibc 符号（$bad 处），说明没走 qcc" >&2
  exit 1
fi
"$QNX_HOST/usr/bin/$NM_TOOL" libssl.a 2>/dev/null | grep -q SSL_set_quic_tls_cbs || {
  echo "错误：libssl.a 里没有 SSL_set_quic_tls_cbs" >&2; exit 1; }

mkdir -p "$INSTALL/lib" "$INSTALL/include"
cp libssl.a libcrypto.a "$INSTALL/lib/"
cp -r include/* "$INSTALL/include/"

echo "==> 完成：$INSTALL/lib/{libssl.a,libcrypto.a}"
