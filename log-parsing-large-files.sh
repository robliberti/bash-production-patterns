#!/usr/bin/env bash
# ------------------------------------------------------------
# log-parsing-large-files.sh
#
# Streaming log parsing using only very portable tools.
# Uses tr safely (line-by-line) to normalize whitespace.
#
# Enable strict error handling:
#   -e       Exit on command failure
#   -u       Error on unset variables
#   pipefail Fail pipeline if any stage fails
# ------------------------------------------------------------
set -euo pipefail

is_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_alpha()   { [[ "$1" =~ ^[A-Za-z]+$ ]]; }
is_alnum()   { [[ "$1" =~ ^[A-Za-z0-9]+$ ]]; }

LOGFILE="${1:-/var/log/app.log}"
TOPN="${2:-20}"

if [[ ! -f "$LOGFILE" ]]; then
  echo "ERROR: Log file not found: $LOGFILE" >&2
  exit 1
fi

if ! is_integer "$TOPN" || [[ "$TOPN" -eq 0 ]]; then
  echo "ERROR: topN must be a positive integer (got: '$TOPN')" >&2
  echo "Usage: $0 /path/to/app.log [topN]" >&2
  exit 1
fi

echo "=== Log Level Counts ==="

debug=0
info=0
warn=0
error_count=0

while IFS= read -r line; do
  # Normalize internal whitespace only (safe)
  # Prevents log formatting variance from fragmenting message grouping.
  # Using tr instead of sed for maximum portability across RHEL variants.
  norm_line=$(printf '%s\n' "$line" | tr -s '[:space:]' ' ')
  # Case-insensitive match via uppercase conversion.
  # Avoids needing multiple patterns and handles inconsistent log casing.
  case "${norm_line^^}" in
    *DEBUG*) ((debug++)) ;;
    *INFO*)  ((info++)) ;;
    *WARN*)  ((warn++)) ;;
    *ERROR*) ((error_count++)) ;;
  esac
done < "$LOGFILE"

printf "DEBUG: %d\n" "$debug"
printf "INFO : %d\n" "$info"
printf "WARN : %d\n" "$warn"
printf "ERROR: %d\n" "$error_count"

echo
echo "=== Top $TOPN Messages ==="
while IFS= read -r line; do                         # Read file line-by-line safely (no word splitting, no backslash escaping)
  printf '%s\n' "$line" | tr -s '[:space:]' ' '     # Normalize internal whitespace to avoid duplicate message fragmentation
done < "$LOGFILE" \                                 # Feed logfile into loop via stdin (avoids subshell pipeline issues)
| sort                                              # Group identical normalized lines together
| uniq -c                                           # Count occurrences of each unique line
| sort -nr                                          # Sort numerically, highest counts first
| head -n "$TOPN"                                   # Show only the top N most frequent messages