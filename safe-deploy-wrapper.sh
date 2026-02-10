#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# safe-deploy-wrapper.sh
# Purpose:
#   A deploy/run wrapper that prevents double-runs, logs steps, and guarantees cleanup.
#
# Usage:
#   ./safe-deploy-wrapper.sh --lock /tmp/deploy.lock -- "your-command --with args"

die() { echo "ERROR: $*" >&2; exit 2; }
log() { echo "[$(date -Is)] $*"; }

LOCKFILE=""
CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock) LOCKFILE="${2:-}"; shift 2 ;;
    --) shift; CMD=("$@"); break ;;
    -h|--help)
      cat <<'EOF'
Usage:
  safe-deploy-wrapper.sh --lock /path/to/lock -- command args...

Example:
  safe-deploy-wrapper.sh --lock /tmp/myjob.lock -- ./deploy.sh prod
EOF
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "${LOCKFILE}" ]] || die "--lock is required"
[[ ${#CMD[@]} -gt 0 ]] || die "Command required after --"

cleanup() {
  local code=$?
  if [[ -n "${LOCKFILE}" && -f "${LOCKFILE}" ]]; then
    rm -f "${LOCKFILE}" || true
    log "Removed lockfile: ${LOCKFILE}"
  fi
  log "Exit code: ${code}"
}
trap cleanup EXIT

# Acquire lock (atomic)
if ( set -o noclobber; echo "$$" > "${LOCKFILE}" ) 2>/dev/null; then
  log "Acquired lock: ${LOCKFILE} (pid=$$)"
else
  holder="$(cat "${LOCKFILE}" 2>/dev/null || true)"
  die "Lock already held at ${LOCKFILE} (holder=${holder})"
fi

log "Running: ${CMD[*]}"
"${CMD[@]}"
log "Success"