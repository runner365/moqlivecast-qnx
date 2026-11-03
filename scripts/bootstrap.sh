#!/usr/bin/env bash
# Fetch upstream moqlivecast at a pinned commit and apply patches/.
# Upstream is referenced by URL — its history is never copied into this repo.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/runner365/moqlivecast.git}"
# PIN THIS before submitting: a moving branch makes the port unreproducible.
#   git -C upstream rev-parse HEAD
UPSTREAM_REF="${UPSTREAM_REF:-master}"
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

echo "==> applying ${#patches[@]} patch(es)"
git -C "$UP_DIR" checkout --quiet -- .
for p in "${patches[@]}"; do
  echo "    $(basename "$p")"
  git -C "$UP_DIR" apply --index --whitespace=fix "$p"
done

echo "==> done: $UP_DIR @ $(git -C "$UP_DIR" rev-parse --short HEAD) +${#patches[@]} patches"
