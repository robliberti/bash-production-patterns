#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# disk-pressure-triage.sh
# Usage: ./disk-pressure-triage.sh [PATH] [DEPTH] [TOPN]
# Example: ./disk-pressure-triage.sh / 2 30

ROOT="${1:-/}"
DEPTH="${2:-2}"
TOPN="${3:-25}"

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

log() { echo "[$(date -Is)] $*"; }

log "Disk overview (df -h) for ${ROOT}"
df -h "${ROOT}" || true

log "Inode overview (df -i) for ${ROOT}"
df -i "${ROOT}" || true

log "Top directories (same filesystem) under ${ROOT} (depth=${DEPTH}, top=${TOPN})"
if have du; then
  # GNU vs BSD du differ; try GNU-ish first then BSD-ish.
  if du -x -d "${DEPTH}" -k "${ROOT}" >/dev/null 2>&1; then
    du -x -d "${DEPTH}" -k "${ROOT}" 2>/dev/null | sort -nr | head -n "${TOPN}" | awk '{printf "%10.2f GB  %s\n", $1/1048576, $2}'
  else
    # macOS/BSD: -d works, -x works, -k works
    du -x -d "${DEPTH}" -k "${ROOT}" 2>/dev/null | sort -nr | head -n "${TOPN}" | awk '{printf "%10.2f GB  %s\n", $1/1048576, $2}'
  fi
else
  die "du not found"
fi

log "Largest files (same filesystem) under ${ROOT} (top=${TOPN})"
if have find; then
  # -xdev is Linux; on macOS it's also supported.
  find "${ROOT}" -xdev -type f -size +200M -print0 2>/dev/null \
    | xargs -0 ls -ln 2>/dev/null \
    | awk '{print $5, $9}' \
    | sort -nr \
    | head -n "${TOPN}" \
    | awk '{printf "%10.2f GB  %s\n", $1/1073741824, $2}'
else
  die "find not found"
fi

log "Large log files under /var/log (top=${TOPN})"
if [[ -d /var/log ]]; then
  find /var/log -type f -size +50M -print0 2>/dev/null \
    | xargs -0 ls -ln 2>/dev/null \
    | awk '{print $5, $9}' \
    | sort -nr \
    | head -n "${TOPN}" \
    | awk '{printf "%10.2f GB  %s\n", $1/1073741824, $2}'
else
  log "/var/log not present"
fi

log "Deleted-but-open files (classic 'disk full but nothing big' scenario)"
if have lsof; then
  # lsof output varies; "deleted" shows in NAME.
  lsof 2>/dev/null | awk 'tolower($0) ~ /deleted/ {print}' | head -n 200 || true
else
  log "lsof not found (install to detect deleted-but-open files)"
fi

log "Done"