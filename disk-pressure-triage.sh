#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# disk-pressure-triage.sh
# Purpose:
#   Fast, safe disk-usage triage without crossing filesystem boundaries.
#   Works on Linux and macOS (BSD) with sensible fallbacks.
#
# Usage:
#   ./disk-pressure-triage.sh [--root PATH] [--depth N] [--topn N]
#                             [--min-file SIZE] [--min-log SIZE]
#                             [--logs-root PATH]
#                             [--check-deleted | --no-check-deleted]
#
# Examples:
#   ./disk-pressure-triage.sh
#   ./disk-pressure-triage.sh --root / --depth 2 --topn 30
#   ./disk-pressure-triage.sh --root /var --min-file 100M --topn 50
#   ./disk-pressure-triage.sh --logs-root /var/log --min-log 50M
#
# Notes:
#   - SIZE values are passed to find -size and should be find-compatible, e.g. 200M, 1G.
#   - This script avoids crossing filesystem boundaries using:
#       du:   -x
#       find: -xdev

ROOT="/"
DEPTH="2"
TOPN="25"
MIN_FILE="200M"
MIN_LOG="50M"
LOGS_ROOT="/var/log"
CHECK_DELETED="1"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

ts() {
  # date -Is (GNU) vs BSD date
  if date -Is >/dev/null 2>&1; then
    date -Is
  else
    date +"%Y-%m-%dT%H:%M:%S%z"
  fi
}

log() { echo "[$(ts)] $*"; }

usage() {
  cat <<'USAGE'
disk-pressure-triage.sh - Disk usage triage without crossing filesystems

Usage:
  ./disk-pressure-triage.sh [--root PATH] [--depth N] [--topn N]
                            [--min-file SIZE] [--min-log SIZE]
                            [--logs-root PATH]
                            [--check-deleted | --no-check-deleted]
  ./disk-pressure-triage.sh --help

Options:
  --root PATH          Root path to analyze (default: /)
  --depth N            Directory depth for du listing (default: 2)
  --topn N             Number of top results to show per section (default: 25)
  --min-file SIZE      Minimum file size for "largest files" scan (default: 200M)
  --min-log SIZE       Minimum log file size for logs scan (default: 50M)
  --logs-root PATH     Where to scan for logs (default: /var/log)
  --check-deleted      Show deleted-but-open files via lsof (default: enabled)
  --no-check-deleted   Skip deleted-but-open files check
  --help               Show this help

Examples:
  ./disk-pressure-triage.sh
  ./disk-pressure-triage.sh --root / --depth 3 --topn 40
  ./disk-pressure-triage.sh --root /var --min-file 100M --topn 50
USAGE
}

# -------------------------
# Arg parsing
# -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2;;
    --depth) DEPTH="${2:-}"; shift 2;;
    --topn) TOPN="${2:-}"; shift 2;;
    --min-file) MIN_FILE="${2:-}"; shift 2;;
    --min-log) MIN_LOG="${2:-}"; shift 2;;
    --logs-root) LOGS_ROOT="${2:-}"; shift 2;;
    --check-deleted) CHECK_DELETED="1"; shift;;
    --no-check-deleted) CHECK_DELETED="0"; shift;;
    --help|-h) usage; exit 0;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done

[[ -n "${ROOT}" ]] || die "--root is required"
[[ -d "${ROOT}" ]] || die "Path not found: ${ROOT}"
[[ "${DEPTH}" =~ ^[0-9]+$ ]] || die "--depth must be an integer"
[[ "${TOPN}" =~ ^[0-9]+$ ]] || die "--topn must be an integer"

have df   || die "df not found"
have du   || die "du not found"
have find || die "find not found"
have sort || die "sort not found"
have awk  || die "awk not found"

echo
log "Disk pressure triage starting"
log "root=${ROOT} depth=${DEPTH} topn=${TOPN} min_file=${MIN_FILE} logs_root=${LOGS_ROOT} min_log=${MIN_LOG} check_deleted=${CHECK_DELETED}"
echo

# -------------------------
# Helpers
# -------------------------
print_kb_path_table_as_gb() {
  # Input: lines "KB PATH"
  # Output: "   XX.XX GB  PATH"
  awk '{printf "%10.2f GB  %s\n", $1/1048576, $2}'
}

print_bytes_path_table_as_gb() {
  # Input: lines "BYTES<TAB>PATH"
  awk -F'\t' '{printf "%10.2f GB  %s\n", $1/1073741824, $2}'
}

du_topdirs() {
  local path="$1" depth="$2" topn="$3"

  # Prefer a single consistent approach: du -x -d DEPTH -k PATH
  # Works on GNU and macOS/BSD. If it fails, fallback to a shallow glob on macOS.
  if du -x -d "${depth}" -k "${path}" >/dev/null 2>&1; then
    du -x -d "${depth}" -k "${path}" 2>/dev/null \
      | sort -nr \
      | head -n "${topn}" \
      | print_kb_path_table_as_gb
  else
    # Fallback: approximate by listing immediate children only (won't include hidden entries)
    du -x -k "${path}"/* 2>/dev/null \
      | sort -nr \
      | head -n "${topn}" \
      | awk '{printf "%10.2f GB  %s\n", $1/1048576, $2}'
  fi
}

supports_find_printf() {
  # BSD find doesn't support -printf
  find "${ROOT}" -xdev -maxdepth 0 -printf '' >/dev/null 2>&1
}

largest_files() {
  local path="$1" min_size="$2" topn="$3"

  if supports_find_printf; then
    # Linux/GNU: safe, handles spaces
    find "${path}" -xdev -type f -size "+${min_size}" -printf '%s\t%p\n' 2>/dev/null \
      | sort -nr \
      | head -n "${topn}" \
      | print_bytes_path_table_as_gb
  else
    # macOS/BSD: use stat safely with -print0
    have stat || die "stat not found (required on macOS fallback path)"
    find "${path}" -xdev -type f -size "+${min_size}" -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do
          # stat -f %z returns size in bytes on macOS/BSD
          sz="$(stat -f '%z' "$f" 2>/dev/null || echo 0)"
          printf "%s\t%s\n" "${sz}" "${f}"
        done \
      | sort -nr \
      | head -n "${topn}" \
      | print_bytes_path_table_as_gb
  fi
}

largest_logs() {
  local logs_root="$1" min_log="$2" topn="$3"

  [[ -d "${logs_root}" ]] || { log "Logs root not present: ${logs_root}"; return 0; }

  if supports_find_printf; then
    find "${logs_root}" -xdev -type f -name "*.log" -size "+${min_log}" -printf '%s\t%p\n' 2>/dev/null \
      | sort -nr \
      | head -n "${topn}" \
      | print_bytes_path_table_as_gb
  else
    have stat || die "stat not found (required on macOS fallback path)"
    find "${logs_root}" -xdev -type f -name "*.log" -size "+${min_log}" -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do
          sz="$(stat -f '%z' "$f" 2>/dev/null || echo 0)"
          printf "%s\t%s\n" "${sz}" "${f}"
        done \
      | sort -nr \
      | head -n "${topn}" \
      | print_bytes_path_table_as_gb
  fi
}

deleted_but_open() {
  if [[ "${CHECK_DELETED}" != "1" ]]; then
    log "Skipping deleted-but-open check"
    return 0
  fi
  if ! have lsof; then
    log "lsof not found (install to detect deleted-but-open files)"
    return 0
  fi

  # lsof can be expensive; keep output bounded
  log "Deleted-but-open files (disk full but nothing big scenario)"
  lsof 2>/dev/null \
    | awk 'tolower($0) ~ /deleted/ {print}' \
    | head -n 200 || true
}

# -------------------------
# Sections
# -------------------------
log "Filesystem usage (df -h) for ${ROOT}"
df -h "${ROOT}" || true
echo

log "Inode usage (df -i) for ${ROOT}"
df -i "${ROOT}" || true
echo

log "Top directories (one filesystem) under ${ROOT} (depth=${DEPTH}, top=${TOPN})"
du_topdirs "${ROOT}" "${DEPTH}" "${TOPN}" || true
echo

log "Largest files (one filesystem) under ${ROOT} (min=${MIN_FILE}, top=${TOPN})"
largest_files "${ROOT}" "${MIN_FILE}" "${TOPN}" || true
echo

log "Large logs (*.log) under ${LOGS_ROOT} (min=${MIN_LOG}, top=${TOPN})"
largest_logs "${LOGS_ROOT}" "${MIN_LOG}" "${TOPN}" || true
echo

deleted_but_open || true
echo

log "Done"