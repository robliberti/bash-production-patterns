#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# k8s-context-guard.sh
# Purpose:
#   Guardrail for scripts that touch Kubernetes. Ensures:
#   - kubectl exists
#   - current context is in an allowlist
#   - namespace is in allowlist (optional)
#   - optional confirmation token required for prod contexts
#
# Usage:
#   ./k8s-context-guard.sh --contexts "dev-cluster,stage-cluster" --namespaces "default,apps" --command "kubectl get pods"
#   ./k8s-context-guard.sh --contexts "prod-cluster" --confirm-token "I_UNDERSTAND" --command "kubectl delete pod xyz -n apps"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date -Is)] $*"; }

CONTEXTS=""
NAMESPACES=""
CONFIRM_TOKEN=""
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contexts) CONTEXTS="${2:-}"; shift 2 ;;
    --namespaces) NAMESPACES="${2:-}"; shift 2 ;;
    --confirm-token) CONFIRM_TOKEN="${2:-}"; shift 2 ;;
    --command) COMMAND="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage:
  k8s-context-guard.sh --contexts "ctx1,ctx2" [--namespaces "ns1,ns2"] [--confirm-token TOKEN] --command "kubectl ..."

Notes:
  - If --confirm-token is provided, you must type it before execution.
EOF
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "${CONTEXTS}" ]] || die "--contexts is required"
[[ -n "${COMMAND}" ]] || die "--command is required"
have kubectl || die "kubectl not found"

current_ctx="$(kubectl config current-context 2>/dev/null || true)"
[[ -n "${current_ctx}" ]] || die "No current kube context set"

# Normalize CSV allowlist
csv_contains() {
  local csv="$1"
  local needle="$2"
  IFS=',' read -r -a arr <<< "${csv}"
  for x in "${arr[@]}"; do
    x="$(echo "$x" | xargs)"
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

log "Current context: ${current_ctx}"
csv_contains "${CONTEXTS}" "${current_ctx}" || die "Context '${current_ctx}' is not allowed. Allowed: ${CONTEXTS}"

if [[ -n "${NAMESPACES}" ]]; then
  # Try to derive current namespace
  current_ns="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
  current_ns="${current_ns:-default}"
  log "Current namespace: ${current_ns}"
  csv_contains "${NAMESPACES}" "${current_ns}" || die "Namespace '${current_ns}' is not allowed. Allowed: ${NAMESPACES}"
fi

if [[ -n "${CONFIRM_TOKEN}" ]]; then
  echo "Confirmation required to proceed."
  echo "Type exactly: ${CONFIRM_TOKEN}"
  read -r typed
  [[ "${typed}" == "${CONFIRM_TOKEN}" ]] || die "Confirmation token mismatch"
fi

log "Executing: ${COMMAND}"
bash -lc "${COMMAND}"
log "Done"