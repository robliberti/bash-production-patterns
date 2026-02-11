#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: svc-debug.sh -s <service> [options]

Options:
  -s <service>   Service name (nginx or nginx.service)
  -r             Restart service
  -f             Follow logs (journalctl -f)
  -b             Use previous boot logs (journalctl -b -1)
  -B             Use current boot logs (default)
  -n <lines>     Number of log lines to show (default: 50)
  -h             Help
EOF
}

SERVICE=""
RESTART=0
FOLLOW=0
BOOT_ARG="-b"
LINES=50

while getopts ":s:rfbBn:h" opt; do
  case "$opt" in
    s) SERVICE="$OPTARG" ;;
    r) RESTART=1 ;;
    f) FOLLOW=1 ;;
    b) BOOT_ARG="-b -1" ;;   # previous boot
    B) BOOT_ARG="-b" ;;      # current boot
    n) LINES="$OPTARG" ;;
    h) usage; exit 0 ;;
    :)
      echo "ERROR: -$OPTARG requires an argument" >&2
      usage; exit 2
      ;;
    \?)
      echo "ERROR: Unknown option -$OPTARG" >&2
      usage; exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

[[ -n "$SERVICE" ]] || { echo "ERROR: -s is required" >&2; usage; exit 2; }

# Normalize service name
SERVICE="${SERVICE%.service}"
UNIT="${SERVICE}.service"

echo "Service: $UNIT"

# Existence check
if ! systemctl show "$UNIT" >/dev/null 2>&1; then
  echo "ERROR: Service $UNIT not found" >&2
  exit 1
fi

echo ">>> Status"
systemctl status "$UNIT" --no-pager || true

if (( RESTART == 1 )); then
  echo ">>> Restarting"
  sudo systemctl restart "$UNIT" || true
  sleep 2
  systemctl status "$UNIT" --no-pager || true
fi

echo ">>> Last $LINES log lines ($BOOT_ARG)"
# shellcheck disable=SC2086
journalctl -u "$UNIT" $BOOT_ARG -n "$LINES" --no-pager || true

if (( FOLLOW == 1 )); then
  echo ">>> Following logs (Ctrl+C to stop)"
  # shellcheck disable=SC2086
  journalctl -fu "$UNIT" $BOOT_ARG
fi