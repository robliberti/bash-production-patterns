#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# http-sla-probe.sh
# Purpose:
#   Probe HTTP endpoints for status code and latency. Useful in CI and runbooks.
#
# Usage:
#   ./http-sla-probe.sh urls.txt [timeout_seconds] [max_ms]
# urls.txt format: one URL per line, comments allowed with #.
#
# Exit codes:
#   0 = all OK
#   1 = at least one failed

FILE="${1:-}"
TIMEOUT="${2:-5}"
MAX_MS="${3:-1500}"

die() { echo "ERROR: $*" >&2; exit 2; }
log() { echo "[$(date -Is)] $*"; }

[[ -n "${FILE}" ]] || die "Usage: $0 urls.txt [timeout_seconds] [max_ms]"
[[ -f "${FILE}" ]] || die "File not found: ${FILE}"
command -v curl >/dev/null 2>&1 || die "curl not found"

fail=0
log "Probing URLs (timeout=${TIMEOUT}s max_ms=${MAX_MS})"

while read -r url; do
  [[ -z "${url}" ]] && continue
  [[ "${url}" =~ ^[[:space:]]*# ]] && continue

  # curl output format: code time_total
  out="$(curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" --max-time "${TIMEOUT}" "${url}" || true)"
  code="$(echo "${out}" | awk '{print $1}')"
  sec="$(echo "${out}" | awk '{print $2}')"
  ms="$(awk -v s="${sec:-999}" 'BEGIN{printf "%.0f", s*1000}')"

  if [[ "${code}" =~ ^2|3 ]] && (( ms <= MAX_MS )); then
    printf "OK    code=%s  latency_ms=%s  %s\n" "${code}" "${ms}" "${url}"
  else
    printf "FAIL  code=%s  latency_ms=%s  %s\n" "${code:-000}" "${ms:-999999}" "${url}"
    fail=1
  fi
done < "${FILE}"

exit "${fail}"