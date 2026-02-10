#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# deploy-guardrails.sh
# Template wrapper: precheck -> deploy -> verify -> (rollback on failure)

log() { echo "[$(date -Is)] $*"; }
die() { log "ERROR: $*"; exit 2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# --- Customizable hooks ---
precheck() {
  log "Precheck: validating dependencies and environment"
  require_cmd bash
  require_cmd curl
  # add: require_cmd kubectl / terraform / aws / az etc
}

deploy() {
  log "Deploy: perform deployment steps"
  # put real deploy commands here
  # Example:
  # ./scripts/build.sh
  # ./scripts/publish.sh
  # kubectl apply -f manifests/
  true
}

verify() {
  log "Verify: check health endpoints / readiness"
  # Example:
  # curl -fsS https://service.example.com/health
  true
}

rollback() {
  log "Rollback: revert to last known good"
  # Example:
  # kubectl rollout undo deploy/my-service
  true
}

# --- Engine ---
on_error() {
  local exit_code=$?
  log "Failure detected (exit=${exit_code}). Starting rollback."
  rollback || log "Rollback failed (manual intervention needed)"
  exit "${exit_code}"
}
trap on_error ERR

main() {
  precheck
  deploy
  verify
  log "Deploy completed successfully"
}

main "$@"