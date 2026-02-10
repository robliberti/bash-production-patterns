#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# service-watchdog.sh
#
# PURPOSE
#   Bash watchdog for a systemd service that:
#     • Monitors a systemd service
#     • Attempts restart if down
#     • Stops after N restarts inside time window (flapping protection)
#     • Sends alert when giving up
#
# -----------------------------------------------------------------------------
# PRODUCTION ALTERNATIVE (RHEL/systemd) — Prefer systemd-native restart + alerting
#
# In real production on RHEL, you typically do NOT run a custom bash watchdog loop.
# You let systemd handle:
#   • automatic restarts
#   • backoff (RestartSec)
#   • flapping protection (StartLimit*)
#   • and failure hooks (OnFailure=) for alerting
#
# This means: yes, you need an *additional* unit (a tiny “alert” service) that
# runs when the main service fails. systemd itself doesn’t email you; it runs
# whatever you point it at (email script, Slack webhook, PagerDuty, etc.).
#
# =============================================================================

# -----------------------------
# Config (override via args)
# -----------------------------
SERVICE="${1:-}"
EMAIL_TO="${2:-}"

if [[ -z "$SERVICE" ]]; then
  echo "Usage: $0 <systemd-service-name> [alert-email]" >&2
  exit 1
fi

# Normalize service name (optional but avoids surprises)
[[ "$SERVICE" != *.service ]] && SERVICE="${SERVICE}.service"

# -----------------------------------------------------------------------------
# Validate service exists (fail fast on typos or invalid input)
#
# We check against installed systemd unit files instead of active units because:
#   • list-unit-files shows ALL installed services (enabled, disabled, stopped)
#   • list-units would miss services that are installed but not currently loaded
#
# This prevents the watchdog from running forever against a non-existent service,
# which would create false operational signals and waste troubleshooting time.
#
# Implementation note:
#   list-unit-files output is typically: "<unitname>.service <state>"
#   So we literal-match "<SERVICE><space>" (no regex needed).
# -----------------------------------------------------------------------------
if ! systemctl list-unit-files --type=service --no-legend 2>/dev/null \
  | grep -qF "$SERVICE "; then
  echo "ERROR: Unknown systemd service: $SERVICE" >&2
  exit 1
fi

# -----------------------------
# Tuning knobs
# -----------------------------
INTERVAL_SEC=10          # how often to check service
WINDOW_SEC=60            # flapping detection window
MAX_RESTARTS=2           # max restarts allowed inside window
RESTART_COOLDOWN_SEC=5   # wait after restart attempt

# -----------------------------
# Environment
# -----------------------------
HOST="$(hostname -f 2>/dev/null || hostname)"
RESTART_TS=()   # array of restart timestamps (epoch seconds)

# -----------------------------
# Logging helpers
# -----------------------------
timestamp() {
  date +'%Y-%m-%d %H:%M:%S'
}

log() {
  # Log format: bracket-delimited structured text logging
  # Pattern: [timestamp] [component] message
  echo "[$(timestamp)] [$SERVICE] $*"
}

# Warn once about alerting configuration
if [[ -z "$EMAIL_TO" ]]; then
  log "WARN: No alert email provided; alert() will log locally only"
fi

if ! command -v mail >/dev/null 2>&1; then
  log "WARN: 'mail' command not found; alert() will log locally only"
fi

# -----------------------------
# Alerting
# -----------------------------
alert() {
  local msg="$1"
  local subject="[ALERT] $SERVICE watchdog on $HOST"

  local payload
  payload="$(
    {
      echo "[$(timestamp)] $msg"
      echo
      echo "==== systemctl status ===="
      systemctl --no-pager -l status "$SERVICE" || true
      echo
      echo "==== recent journal ===="
      journalctl -u "$SERVICE" --no-pager -n 50 || true
    } 2>&1
  )"

  # If mail/email not configured, do a reliable local fallback
  if [[ -z "$EMAIL_TO" ]] || ! command -v mail >/dev/null 2>&1; then
    echo "$payload" >&2
    return 0
  fi

  printf '%s\n' "$payload" | mail -s "$subject" "$EMAIL_TO" || {
    # If mail fails, fall back to stderr (don’t lose the alert)
    echo "$payload" >&2
  }
}

# -----------------------------
# Restart window pruning
# -----------------------------
prune_old_restarts() {
  local now
  now="$(date +%s)"

  local kept=()
  local t

  for t in "${RESTART_TS[@]}"; do
    if (( now - t <= WINDOW_SEC )); then
      kept+=("$t")
    fi
  done

  RESTART_TS=("${kept[@]}")
}

# -----------------------------
# Service state helpers
# -----------------------------
is_active() {
  systemctl is-active --quiet "$SERVICE"
}

try_restart() {
  systemctl restart "$SERVICE"
}

# =============================================================================
# Main Loop
# =============================================================================
log "Starting watchdog (interval=${INTERVAL_SEC}s window=${WINDOW_SEC}s max_restarts=${MAX_RESTARTS})"

while true; do

  # Service healthy
  if is_active; then
    sleep "$INTERVAL_SEC"
    continue
  fi

  log "Service DOWN detected"

  prune_old_restarts

  # Too many restarts recently → give up + alert
  if (( ${#RESTART_TS[@]} >= MAX_RESTARTS )); then
    alert "Service DOWN and restart limit exceeded (${#RESTART_TS[@]} restarts in ${WINDOW_SEC}s). Giving up."
    exit 2
  fi

  log "Attempting restart..."

  RESTART_TS+=("$(date +%s)")

  if try_restart; then
    sleep "$RESTART_COOLDOWN_SEC"

    if is_active; then
      log "Restart succeeded"
    else
      log "Restart issued but service still not active"
    fi
  else
    log "Restart command failed"
  fi

  sleep "$INTERVAL_SEC"

done