#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# temp-files-multiple.sh
#
# Production-safe management of multiple temp files.
#
# Why:
# - Prevents temp file leaks
# - Handles signals safely
# - Supports unlimited temp allocations
# ------------------------------------------------------------

TMPFILES=()

new_tmp() {
  local f
  f="$(mktemp)"
  TMPFILES+=("$f")
  echo "$f"
}

cleanup() {
  if [[ ${#TMPFILES[@]} -gt 0 ]]; then
    rm -f "${TMPFILES[@]}"
  fi
}

trap cleanup EXIT INT TERM

# Example usage
tmp1="$(new_tmp)"
tmp2="$(new_tmp)"

echo "hello world" > "$tmp1"
echo "another temp file" > "$tmp2"

cat "$tmp1"
cat "$tmp2"