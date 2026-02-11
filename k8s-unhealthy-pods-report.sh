#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# k8s-unhealthy-pods-report.sh
#
# Purpose:
#   DevOps-y example demonstrating:
#     • Safe line-oriented looping using: while IFS= read -r ... done < <(cmd)
#     • A heredoc to generate a config/runbook artifact
#
# What it does:
#   1) Finds pods that are NOT in Running phase in a namespace
#   2) Writes a simple report file listing pod + phase
#   3) Generates a small YAML "debug config" file via heredoc referencing the report
#
# Usage:
#   ./k8s-unhealthy-pods-report.sh [namespace]
#
# Examples:
#   ./k8s-unhealthy-pods-report.sh
#   ./k8s-unhealthy-pods-report.sh kube-system
#
# Requirements:
#   • kubectl configured to talk to a cluster
# -----------------------------------------------------------------------------

NAMESPACE="${1:-default}"
REPORT_FILE="pod_health_report_${NAMESPACE}.txt"
CONFIG_FILE="debug_config_${NAMESPACE}.yaml"

have() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 2; }
log() { echo "[$(date -Is)] $*"; }

have kubectl || die "kubectl not found in PATH"

log "Namespace: ${NAMESPACE}"
log "Report:    ${REPORT_FILE}"
log "Config:    ${CONFIG_FILE}"

# Clear/initialize report file
: > "$REPORT_FILE"

# Get unhealthy pod names (phase != Running). Output one name per line.
# Note: This is intentionally line-oriented output to demonstrate safe looping.
UNHEALTHY_PODS_CMD=(
  kubectl get pods -n "$NAMESPACE"
  --field-selector=status.phase!=Running
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

log "Collecting non-Running pods..."
pod_count=0

# -----------------------------------------------------------------------------
# SAFE LOOP:
#   - IFS= : don't trim leading/trailing whitespace
#   - -r  : don't treat backslashes as escapes
#   - < <(cmd) : process substitution so loop runs in current shell (no subshell)
# -----------------------------------------------------------------------------
while IFS= read -r pod; do
  # Skip empty lines (can happen if there are no items)
  [[ -n "$pod" ]] || continue

  ((pod_count++))
  phase="$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "UNKNOWN")"
  printf "%-48s %s\n" "$pod" "$phase" >> "$REPORT_FILE"
done < <("${UNHEALTHY_PODS_CMD[@]}")

log "Found ${pod_count} non-Running pod(s)."
log "Wrote report to ${REPORT_FILE}"

# -----------------------------------------------------------------------------
# HEREDOC EXAMPLE:
#   Generates a YAML artifact you could check into a ticket, attach to an incident,
#   or feed into another tool. Variables expand because we used <<EOF (not quoted).
# -----------------------------------------------------------------------------
cat <<EOF > "$CONFIG_FILE"
# Auto-generated debug config / runbook stub
namespace: ${NAMESPACE}
generated_at: $(date -Is)
report_file: ${REPORT_FILE}
non_running_pod_count: ${pod_count}

triage:
  quick_checks:
    - "kubectl get pods -n ${NAMESPACE} -o wide"
    - "kubectl describe pod <pod> -n ${NAMESPACE}"
    - "kubectl logs <pod> -n ${NAMESPACE} --all-containers --tail=200"
    - "kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp | tail -n 50"

notes: |
  This file was generated because pods were detected in a non-Running phase.
  See the report file for the pod list and phases.

  Common causes:
    • ImagePullBackOff / ErrImagePull (registry auth, image tag, network)
    • CrashLoopBackOff (app crash, bad config, missing secret)
    • Pending (insufficient resources, node selectors/taints, PVC issues)

EOF

log "Wrote config to ${CONFIG_FILE}"

# Helpful console output
echo
echo "==== Summary ===="
echo "Namespace: $NAMESPACE"
echo "Non-Running pods: $pod_count"
echo "Report: $REPORT_FILE"
echo "Config: $CONFIG_FILE"
echo

# Optional: show report content if any pods found
if (( pod_count > 0 )); then
  echo "---- Report (first 50 lines) ----"
  head -n 50 "$REPORT_FILE"
else
  echo "No non-Running pods found in namespace '$NAMESPACE'."
fi