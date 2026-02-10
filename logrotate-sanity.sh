#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# logrotate-sanity.sh
# Usage: ./logrotate-sanity.sh [log_dir] [topn]
# Example: ./logrotate-sanity.sh /var/log 30

LOG_DIR="${1:-/var/log}"
TOPN="${2:-30}"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date -Is)] $*"; }

[[ -d "${LOG_DIR}" ]] || die "Log directory not found: ${LOG_DIR}"

log "Largest files in ${LOG_DIR} (top=${TOPN})"
find "${LOG_DIR}" -type f -size +20M -print0 2>/dev/null \
  | xargs -0 ls -ln 2>/dev/null \
  | awk '{print $5, $9}' \
  | sort -nr \
  | head -n "${TOPN}" \
  | awk '{printf "%10.2f MB  %s\n", $1/1048576, $2}'

log "Largest directories under ${LOG_DIR} (depth=2)"
if du -x -d 2 -k "${LOG_DIR}" >/dev/null 2>&1; then
  du -x -d 2 -k "${LOG_DIR}" 2>/dev/null | sort -nr | head -n "${TOPN}" \
    | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
else
  du -k "${LOG_DIR}"/* 2>/dev/null | sort -nr | head -n "${TOPN}" \
    | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
fi

log "Check for logrotate"
if have logrotate; then
  log "logrotate found: $(command -v logrotate)"
  # Common status locations
  for f in /var/lib/logrotate/status /var/lib/logrotate/logrotate.status /var/lib/logrotate.status; do
    if [[ -f "$f" ]]; then
      log "Found logrotate status file: $f"
      tail -n 5 "$f" || true
      break
    fi
  done

  # Show timer/service info if systemd exists
  if have systemctl; then
    log "systemd timers/services related to logrotate (if present)"
    systemctl list-timers --all 2>/dev/null | awk 'tolower($0) ~ /logrotate/ {print}' || true
    systemctl status logrotate.service 2>/dev/null | head -n 30 || true
  fi
else
  log "logrotate not found"
fi

log "Done"