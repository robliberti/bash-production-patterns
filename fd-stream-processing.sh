#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# fd-stream-processing.sh
#
# Demonstrates explicit file descriptor usage for safe,
# high-performance stream processing in Bash.
#
# Why:
# - Avoids subshell side effects
# - Allows parallel file reads
# - Gives fine control over resource lifecycle
# ------------------------------------------------------------

INPUT_FILE="${1:-input.txt}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: File not found: $INPUT_FILE" >&2
  exit 1
fi

# Open file on FD 3
exec 3< "$INPUT_FILE"

line_count=0

while IFS= read -r line <&3; do
  ((line_count++))

  # Example processing
  if [[ "$line" == *ERROR* ]]; then
    echo "ERROR LINE: $line"
  fi

done

# Close FD explicitly
exec 3<&-

echo "Processed $line_count lines"