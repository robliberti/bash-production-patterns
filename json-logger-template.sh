#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# json-logger-template.sh
# Use: log_json LEVEL "message" "key1=value1" "key2=value2"

escape_json() {
  # Minimal JSON string escape (no external deps).
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

log_json() {
  local level="$1"; shift
  local msg="$1"; shift

  local ts
  ts="$(date -Is)"

  local extra=""
  local kv
  for kv in "$@"; do
    local k="${kv%%=*}"
    local v="${kv#*=}"
    extra+=",\"$(escape_json "$k")\":\"$(escape_json "$v")\""
  done

  printf '{"timestamp":"%s","level":"%s","message":"%s"%s}\n' \
    "$(escape_json "$ts")" \
    "$(escape_json "$level")" \
    "$(escape_json "$msg")" \
    "$extra"
}

# Example
if [[ "${1:-}" == "--example" ]]; then
  log_json INFO "starting" service=disk-triage host="$(hostname)"
  log_json WARN "disk high" mount=/ percent=92
fi