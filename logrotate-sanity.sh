#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# logrotate-sanity.sh
#
# Purpose:
#   Quick triage for log growth + sanity check that logrotate is present and running.
#
# Usage:
#   ./logrotate-sanity.sh [log_dir] [topn]
# Example:
#   ./logrotate-sanity.sh /var/log 30

LOG_DIR="${1:-/var/log}"
TOPN="${2:-30}"

log() { echo "[$(date -Is)] $*"; }
err() { echo "[$(date -Is)] ERROR: $*" >&2; }
die() { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
require() {
  for tool in "$@"; do
    have "$tool" || die "Missing required tool: $tool"
  done
}
is_uint() [[ "${1:-}" =~ ^[0-9]+$ ]]

# ---- validation ----
[[ -d "${LOG_DIR}" ]] || die "Log directory not found: ${LOG_DIR}"
is_uint "${TOPN}" || die "TOPN must be an integer, got: ${TOPN}"
(( TOPN > 0 )) || die "TOPN must be > 0, got: ${TOPN}"

# Base tools needed for the scan portions
require find xargs ls awk sort head

log "Largest files in ${LOG_DIR} (top=${TOPN}, >20MB)"
# NOTE: filename display can be imperfect for paths with spaces due to ls/awk parsing.
find "${LOG_DIR}" -type f -size +20M -print0 2>/dev/null \
  | xargs -0 ls -ln 2>/dev/null \
  | awk '{print $5, $9}' \
  | sort -nr \
  | head -n "${TOPN}" \
  | awk '{printf "%10.2f MB  %s\n", $1/1048576, $2}'
echo

log "Largest directories under ${LOG_DIR} (depth=2)"
# Avoid running du twice by capturing output once.
if have du; then
  if du_out="$(du -x -d 2 -k "${LOG_DIR}" 2>/dev/null)"; then
    printf '%s\n' "${du_out}" | sort -nr | head -n "${TOPN}" \
      | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
  else
    # macOS fallback: some du variants don't support -d; approximate by listing immediate children.
    du -k "${LOG_DIR}"/* 2>/dev/null | sort -nr | head -n "${TOPN}" \
      | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
  fi
else
  log "du not found; skipping directory size listing"
fi
echo

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
  else
    log "systemctl not found; skipping systemd checks"
  fi
else
  log "logrotate not found"
fi

log "Done"