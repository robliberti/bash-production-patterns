#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# mtu-path-check.sh
#
# Purpose:
#   Quick MTU (Maximum Transmission Unit) / Path MTU diagnostics tool.
#
#   Helps answer:
#     • What MTU is my local interface configured for?
#     • What is the largest packet size that can traverse the network path
#       to a destination WITHOUT fragmentation?
#
#   This is useful when debugging:
#     • VPN tunnels (WireGuard, IPsec, OpenVPN)
#     • Overlay networking (VXLAN, Kubernetes CNI)
#     • TLS / HTTPS stalls or partial connection failures
#     • “Ping works but real traffic fails” situations
#
#   The script:
#     1. Displays local interface MTU configuration
#     2. Uses DF (Don't Fragment) pings to estimate Path MTU
#     3. Uses binary search to quickly find max safe payload size
#
# Usage:
#   ./mtu-path-check.sh <host> [iface]
#
# Examples:
#   ./mtu-path-check.sh 8.8.8.8
#   ./mtu-path-check.sh 10.0.0.1 wg0
#
# Notes:
#   • IPv4 packet size = payload + 28 bytes (20 IP + 8 ICMP headers)
#   • Typical Ethernet MTU = 1500 → max ICMP payload ≈ 1472
#   • TCP MSS typically ≈ MTU - 40 (IP + TCP headers)
# -----------------------------------------------------------------------------


HOST="${1:-}"
IFACE="${2:-}"

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date -Is)] $*"; }

[[ -n "${HOST}" ]] || die "Usage: $0 <host> [iface]"

# -----------------------------------------------------------------------------
# show_local_mtu()
#
# Displays MTU configuration for local interfaces.
#
# Why this matters:
#   Path MTU can never exceed local interface MTU.
#   If local MTU is already reduced (ex: VPN or tunnel), that becomes the ceiling.
#
# Supports:
#   • ip (modern Linux)
#   • ifconfig (legacy / BSD / macOS)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# find_max_payload_ipv4()
#
# Determines largest ICMP payload that can be sent WITHOUT fragmentation.
#
# Method:
#   • Uses DF (Don't Fragment) bit
#   • Uses binary search to efficiently find max working size
#
# Why DF matters:
#   If packet exceeds path MTU and DF is set:
#     → Router drops packet
#     → Allows detection of MTU boundary
#
# Why binary search:
#   Faster than linear decrement testing
#   Good for automation / scripting environments
#
# Limitations:
#   • If ICMP is blocked, results may be inconclusive
#   • Some networks silently drop oversized packets
# -----------------------------------------------------------------------------
find_max_payload_ipv4() {
  log "Finding max IPv4 ping payload with DF bit set to ${HOST}"
  if ! have ping; then
    log "ping not found"
    return 0
  fi

  # Try Linux ping syntax first: -M do
  # Binary search bounds
  # 1200 chosen as safe lower bound across most tunnel environments
  # 1472 chosen as typical max for MTU 1500 Ethernet
  local low=1200
  local high=1472
  local best=0

  # Quick pre-check
  # Basic reachability check (not MTU-related, just sanity check)
  if ping -c 1 -W 2 "${HOST}" >/dev/null 2>&1; then
    log "Basic reachability OK"
  else
    log "Host not reachable by basic ping, continuing anyway"
  fi

  # Detect ping implementation differences
  # Linux: supports -M do for DF
  # BSD/macOS: uses -D for DF
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