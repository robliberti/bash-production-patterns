#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# mtu-path-check.sh
# Purpose:
#   Quick MTU/path checks:
#   - Show local interface MTU
#   - Attempt "do not fragment" pings to find max safe payload
#
# Usage:
#   ./mtu-path-check.sh <host> [iface]
# Examples:
#   ./mtu-path-check.sh 8.8.8.8
#   ./mtu-path-check.sh 10.0.0.1 wg0

HOST="${1:-}"
IFACE="${2:-}"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date -Is)] $*"; }

[[ -n "${HOST}" ]] || die "Usage: $0 <host> [iface]"

# Local MTU display
show_local_mtu() {
  log "Local MTU info"
  if have ip; then
    if [[ -n "${IFACE}" ]]; then
      ip link show dev "${IFACE}" | awk '/mtu/ {print}'
    else
      ip -o link show | awk '{print $2, $0}' | sed 's/://g' | awk '/mtu/ {print}'
    fi
  elif have ifconfig; then
    if [[ -n "${IFACE}" ]]; then
      ifconfig "${IFACE}" | awk '/mtu/ {print}'
    else
      ifconfig -a | awk '/mtu/ {print}'
    fi
  else
    log "No ip/ifconfig available to show MTU"
  fi
}

# Find max payload with DF set:
# IPv4 total packet size = payload + 28 (IP+ICMP headers)
# So if MTU is 1500, typical max ping payload is 1472.
find_max_payload_ipv4() {
  log "Finding max IPv4 ping payload with DF bit set to ${HOST}"
  if ! have ping; then
    log "ping not found"
    return 0
  fi

  # Try Linux ping syntax first: -M do
  local low=1200
  local high=1472
  local best=0

  # Quick pre-check
  if ping -c 1 -W 2 "${HOST}" >/dev/null 2>&1; then
    log "Basic reachability OK"
  else
    log "Host not reachable by basic ping, continuing anyway"
  fi

  # Determine ping flavor
  local linux_df_ok=0
  if ping -c 1 -W 2 -M do -s 1400 "${HOST}" >/dev/null 2>&1; then
    linux_df_ok=1
  fi

  while (( low <= high )); do
    local mid=$(( (low + high) / 2 ))
    if (( linux_df_ok == 1 )); then
      if ping -c 1 -W 2 -M do -s "${mid}" "${HOST}" >/dev/null 2>&1; then
        best="${mid}"
        low=$(( mid + 1 ))
      else
        high=$(( mid - 1 ))
      fi
    else
      # macOS/BSD ping: -D sets DF on IPv4; timeout uses -t (TTL) so just use count and rely on default.
      if ping -c 1 -D -s "${mid}" "${HOST}" >/dev/null 2>&1; then
        best="${mid}"
        low=$(( mid + 1 ))
      else
        high=$(( mid - 1 ))
      fi
    fi
  done

  if (( best > 0 )); then
    local mtu_est=$(( best + 28 ))
    log "Max IPv4 payload (DF) ~ ${best} bytes"
    log "Estimated path MTU ~ ${mtu_est} bytes (payload + 28)"
    log "Tip: For TCP MSS, subtract IP+TCP headers too (typical: MTU 1500 -> MSS 1460)."
  else
    log "Could not determine max payload. Possible ICMP blocked or DF not supported."
  fi
}

show_local_mtu
find_max_payload_ipv4
log "Done"