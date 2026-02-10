#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# jsonlog-summary.sh
# Purpose:
#   Summarize "flat-ish" JSON logs by a key without jq.
#   Example log line: {"ts":"...","level":"ERROR","msg":"..."}
#
# Usage:
#   ./jsonlog-summary.sh app.log level
#   ./jsonlog-summary.sh app.log status

FILE="${1:-}"
KEY="${2:-}"

die() { echo "ERROR: $*" >&2; exit 2; }

[[ -n "${FILE}" && -n "${KEY}" ]] || die "Usage: $0 <file> <key>"
[[ -f "${FILE}" ]] || die "File not found: ${FILE}"

# naive JSON key extraction: "key":"VALUE"
# For simple logs where values do not contain unescaped quotes.
grep -o "\"${KEY}\":[ ]*\"[^\"]*\"" "${FILE}" 2>/dev/null \
  | sed -E "s/\"${KEY}\":[ ]*\"//; s/\"$//" \
  | sort \
  | uniq -c \
  | sort -nr \
  | awk '{printf "%8d  %s\n", $1, $2}'