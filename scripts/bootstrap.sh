#!/usr/bin/env bash
# Fetch upstream moqlivecast at a pinned commit and apply patches/.
# Upstream is referenced by URL — its history is never copied into this repo.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/runner365/moqlivecast.git}"
# 固定 commit，保证任何人任何时候克隆到的都是同一份代码。
# 这是上游合入 QNX 支持（POSIX 头文件 + OpenSSL 交叉编译）之后的提交。
# 升级方式：改这里的 SHA，然后重新跑本脚本与 build.sh 验证。
UPSTREAM_REF="${UPSTREAM_REF:-bfd9897071d1}"
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
