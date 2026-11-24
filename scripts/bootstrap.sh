#!/usr/bin/env bash
# Fetch upstream moqlivecast at a pinned commit and apply patches/.
# Upstream is referenced by URL — its history is never copied into this repo.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/runner365/moqlivecast.git}"
# 固定 commit，保证任何人任何时候克隆到的都是同一份代码。
# 该提交包含：QNX 构建支持（POSIX 头文件 + OpenSSL 交叉编译）、
# media_source C API、per-frame 调试日志（MOQ_CLIENT_DEBUG /
# MOQ_STREAM_DEBUG），以及 flv2moqtransport_client 的命令行参数、日志文件
# 和 --only-video / --only-audio 选项（测量时只推视频，排除音频干扰）。
# 升级方式：改这里的 SHA，然后重新跑本脚本与 build.sh 验证。
UPSTREAM_REF="${UPSTREAM_REF:-6b901229c3c1afb75d69868babf7e944f9ef776b}"
UP_DIR="${UP_DIR:-$ROOT/upstream}"

if [ -d "$UP_DIR/.git" ]; then
  echo "==> upstream already present, fetching $UPSTREAM_REF"
  git -C "$UP_DIR" fetch --all --tags --quiet
else
  echo "==> cloning $UPSTREAM_URL"
  git clone --quiet "$UPSTREAM_URL" "$UP_DIR"
fi

echo "==> checkout $UPSTREAM_REF"
git -C "$UP_DIR" checkout --quiet "$UPSTREAM_REF"
echo "    upstream HEAD = $(git -C "$UP_DIR" rev-parse HEAD)"

shopt -s nullglob
patches=("$ROOT"/patches/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  echo "==> no patches yet (patches/*.patch) — clean upstream checkout"
  exit 0
fi

echo "==> applying ${#patches[@]} patch(es) (idempotent)"
git -C "$UP_DIR" checkout --quiet -- .
applied=0
skipped=0
for p in "${patches[@]}"; do
  name=$(basename "$p")
  # 已经合入上游的补丁：反向应用可以成功 => 内容已存在，跳过
  if git -C "$UP_DIR" apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "    $name  (已在源码中，跳过)"
    skipped=$((skipped + 1))
    continue
  fi
  if git -C "$UP_DIR" apply --index --whitespace=fix "$p"; then
    echo "    $name  (已应用)"
    applied=$((applied + 1))
  else
    echo "错误：$name 无法应用，可能上游已改动相关代码" >&2
    exit 1
  fi
done

echo "==> done: $UP_DIR @ $(git -C "$UP_DIR" rev-parse --short HEAD) applied=$applied skipped=$skipped"
