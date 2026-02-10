#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# disk-pressure-triage.sh
# Purpose:
#   Quickly find disk hogs without crossing filesystem boundaries.
#
# Usage:
#   ./disk-pressure-triage.sh [path] [topn]
# Examples:
#   ./disk-pressure-triage.sh / 50
#   ./disk-pressure-triage.sh /var 30

PATH_ROOT="${1:-/}"
TOPN="${2:-30}"

die() { echo "ERROR: $*" >&2; exit 2; }
log() { echo "[$(date -Is)] $*"; }

[[ -d "${PATH_ROOT}" ]] || die "Path not found: ${PATH_ROOT}"

log "Filesystem usage (df -h)"
df -h || true
echo

log "Top directories under ${PATH_ROOT} (one filesystem, depth=2)"
if du -x -d 2 -k "${PATH_ROOT}" >/dev/null 2>&1; then
  du -x -d 2 -k "${PATH_ROOT}" 2>/dev/null | sort -nr | head -n "${TOPN}" \
    | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
else
  # macOS fallback
  du -x -k "${PATH_ROOT}"/* 2>/dev/null | sort -nr | head -n "${TOPN}" \
    | awk '{printf "%10.2f MB  %s\n", $1/1024, $2}'
fi
echo

log "Largest files under ${PATH_ROOT} (one filesystem, >100MB)"
find "${PATH_ROOT}" -xdev -type f -size +100M -print0 2>/dev/null \
  | xargs -0 ls -ln 2>/dev/null \
  | awk '{print $5, $9}' \
  | sort -nr \
  | head -n "${TOPN}" \
  | awk '{printf "%10.2f MB  %s\n", $1/1048576, $2}'
echo

log "Large logs (*.log >50MB) under ${PATH_ROOT}"
find "${PATH_ROOT}" -xdev -type f -name "*.log" -size +50M -print 2>/dev/null | head -n "${TOPN}" || true
echo

log "Done"