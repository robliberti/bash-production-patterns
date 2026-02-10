#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# with-lock.sh
# Usage:
#   ./with-lock.sh /tmp/myjob.lock -- command arg1 arg2
# Example:
#   ./with-lock.sh /tmp/disk-job.lock -- ./disk-pressure-triage.sh / 2 25

LOCKFILE="${1:-}"
shift || true

[[ -n "${LOCKFILE}" ]] || { echo "Usage: $0 /path/to.lock -- command ..." >&2; exit 2; }
[[ "${1:-}" == "--" ]] || { echo "Usage: $0 /path/to.lock -- command ..." >&2; exit 2; }
shift || true

# Lock via atomic mkdir (portable)
LOCKDIR="${LOCKFILE}.d"

cleanup() {
  # Only remove if we own it
  if [[ -f "${LOCKDIR}/pid" ]]; then
    local pid
    pid="$(cat "${LOCKDIR}/pid" 2>/dev/null || true)"
    if [[ "${pid}" == "$$" ]]; then
      rm -rf "${LOCKDIR}" || true
    fi
  fi
}
trap cleanup EXIT INT TERM

if mkdir "${LOCKDIR}" 2>/dev/null; then
  echo "$$" > "${LOCKDIR}/pid"
else
  if [[ -f "${LOCKDIR}/pid" ]]; then
    echo "Lock held by PID: $(cat "${LOCKDIR}/pid" 2>/dev/null || echo '?')" >&2
  else
    echo "Lock held (no pid file found)." >&2
  fi
  exit 0
fi

exec "$@"