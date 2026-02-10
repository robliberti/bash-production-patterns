#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# port-health-sweep.sh
# Usage:
#   ./port-health-sweep.sh hosts.txt [timeout_seconds] [--json]
#
# hosts.txt format:
#   host port [name]
# Example:
#   api.example.com 443 api
#   10.0.1.5 5432 postgres
#
# Output:
#   Plain:  OK/FAIL lines
#   JSON:   one JSON object per line

FILE="${1:-}"
TIMEOUT="${2:-3}"
MODE="${3:-}"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ -n "${FILE}" ]] || die "Usage: $0 hosts.txt [timeout_seconds] [--json]"
[[ -f "${FILE}" ]] || die "File not found: ${FILE}"

is_json=0
if [[ "${MODE}" == "--json" ]]; then
  is_json=1
fi

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

check_port() {
  local host="$1"
  local port="$2"

  # Prefer nc if present, else bash /dev/tcp
  if have nc; then
    nc -z -w "${TIMEOUT}" "${host}" "${port}" >/dev/null 2>&1
  else
    # /dev/tcp works in bash, not in sh
    timeout_cmd=""
    if have timeout; then
      timeout_cmd="timeout ${TIMEOUT}"
    fi
    bash -lc "${timeout_cmd} bash -c 'cat < /dev/null > /dev/tcp/${host}/${port}'" >/dev/null 2>&1
  fi
}

ts_now() { date -Is; }

while read -r line; do
  [[ -z "${line}" ]] && continue
  [[ "${line}" =~ ^[[:space:]]*# ]] && continue

  host="$(echo "${line}" | awk '{print $1}')"
  port="$(echo "${line}" | awk '{print $2}')"
  name="$(echo "${line}" | awk '{print $3}')"
  [[ -n "${host}" && -n "${port}" ]] || continue

  start="$(ts_now)"
  if check_port "${host}" "${port}"; then
    status="OK"
    ok=1
  else
    status="FAIL"
    ok=0
  fi
  end="$(ts_now)"

  if (( is_json == 1 )); then
    printf '{"timestamp":"%s","host":"%s","port":%s,"name":"%s","status":"%s","ok":%d}\n' \
      "$(escape_json "${end}")" \
      "$(escape_json "${host}")" \
      "${port}" \
      "$(escape_json "${name:-}")" \
      "$(escape_json "${status}")" \
      "${ok}"
  else
    printf "%-4s  %-30s  %-6s  %-20s  start=%s end=%s\n" \
      "${status}" "${host}" "${port}" "${name:-}" "${start}" "${end}"
  fi
done < "${FILE}"