#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# safe-ci-script-template.sh
#
# Production-safe Bash template for CI/CD and automation.
# ------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
TS_FORMAT='%Y-%m-%d %H:%M:%S'   # Single source of truth for log timestamps

timestamp() {
  date +"$TS_FORMAT"
}

# Log format: bracket-delimited structured text logging
# Pattern: [timestamp] [component] message
# Provides consistent, grep-friendly logs without the verbosity of JSON logging.
log() {
  echo "[$(timestamp)] [$SCRIPT_NAME] $*"
}

error() {
  echo "[$(timestamp)] [ERROR] $*" >&2
}

cleanup() {
  log "Running cleanup"
}
trap cleanup EXIT INT TERM

require_cmd() {
  # Accepts 1+ command names: require_cmd awk sed grep
  local missing=0

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Required command missing: $cmd"
      missing=1
    fi
  done

  # Fail after checking all of them (better UX than failing on the first)
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

require_cmd awk sed grep

log "Starting job"

# Example workload
sleep 1

log "Job completed successfully"