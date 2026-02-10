#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# incident-snapshot.sh
# Usage: sudo ./incident-snapshot.sh [/path/to/output-dir]
# Produces a timestamped bundle with common system diagnostics.

OUT_BASE="${1:-/tmp}"
TS="$(date +%Y%m%dT%H%M%S)"
HOST="$(hostname 2>/dev/null || echo unknown)"
OUT_DIR="${OUT_BASE%/}/incident_${HOST}_${TS}"

mkdir -p "${OUT_DIR}"

run() {
  local name="$1"; shift
  {
    echo "### COMMAND: $*"
    echo "### TIME: $(date -Is)"
    echo
    "$@" || true
  } > "${OUT_DIR}/${name}.txt" 2>&1
}

run "uname" uname -a
run "uptime" uptime
run "df_h" df -h
run "df_i" df -i
run "mount" mount
run "ps_top_cpu" bash -lc 'ps aux | sort -nrk 3,3 | head -n 40'
run "ps_top_mem" bash -lc 'ps aux | sort -nrk 4,4 | head -n 40'
run "netstat" bash -lc 'netstat -an 2>/dev/null | head -n 200'
run "ss" bash -lc 'ss -tulpen 2>/dev/null | head -n 200'
run "ip_addr" bash -lc 'ip addr 2>/dev/null || ifconfig -a 2>/dev/null'
run "ip_route" bash -lc 'ip route 2>/dev/null || route -n 2>/dev/null'
run "dmesg_tail" bash -lc 'dmesg 2>/dev/null | tail -n 200'
run "journal_tail" bash -lc 'journalctl -n 300 --no-pager 2>/dev/null'
run "syslog_tail" bash -lc 'tail -n 300 /var/log/syslog 2>/dev/null || tail -n 300 /var/log/messages 2>/dev/null'

if command -v lsof >/dev/null 2>&1; then
  run "lsof_deleted" bash -lc 'lsof 2>/dev/null | awk "tolower(\$0) ~ /deleted/ {print}" | head -n 500'
fi

# Optional: tar it
TAR="${OUT_DIR}.tar.gz"
tar -czf "${TAR}" -C "$(dirname "${OUT_DIR}")" "$(basename "${OUT_DIR}")" 2>/dev/null || true

echo "Snapshot saved:"
echo "  Directory: ${OUT_DIR}"
echo "  Archive:   ${TAR}"