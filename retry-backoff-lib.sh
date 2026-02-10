#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# retry-backoff-lib.sh
# Source this file or copy functions into other scripts.

log() { echo "[$(date -Is)] $*"; }

# retry <attempts> <base_delay_sec> <command...>
# Example: retry 5 2 curl -fsS https://example.com/health
retry() {
  local attempts="$1"
  local base_delay="$2"
  shift 2

  local i=1
  while (( i <= attempts )); do
    if "$@"; then
      return 0
    fi

    local exit_code=$?
    local sleep_for=$(( base_delay * i ))

    # Simple jitter: add 0..1 seconds if awk available, else none
    local jitter=0
    if command -v awk >/dev/null 2>&1; then
      jitter="$(awk 'BEGIN{srand(); printf("%d\n", rand()*2)}')"
    fi
    sleep_for=$(( sleep_for + jitter ))

    log "Retry ${i}/${attempts} failed (exit=${exit_code}). Sleeping ${sleep_for}s: $*"
    sleep "${sleep_for}"
    (( i++ ))
  done

  log "All retries failed: $*"
  return 1
}

# Example self-test
if [[ "${1:-}" == "--self-test" ]]; then
  retry 3 1 bash -lc 'exit 1' || true
fi