#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# release-notes-from-git.sh
# Usage:
#   ./release-notes-from-git.sh v1.2.3 v1.2.4
#   ./release-notes-from-git.sh v1.2.3 HEAD
#
# Output:
#   Markdown bullets with commits and optional ticket keys.

die() { echo "ERROR: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

FROM="${1:-}"
TO="${2:-}"

[[ -n "${FROM}" && -n "${TO}" ]] || die "Usage: $0 <from_ref> <to_ref>"
have git || die "git not found"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git repo"

echo "# Release notes: ${FROM} -> ${TO}"
echo
echo "## Changes"
echo

# Format: shortsha subject (author)
git log --no-merges --pretty=format:'- %h %s (%an)' "${FROM}..${TO}" \
  | sed 's/[[:space:]]\+$//' \
  | while read -r line; do
      # Extract ticket-like keys: ABC-123 (optional)
      ticket="$(echo "$line" | grep -Eo '[A-Z]{2,10}-[0-9]+' | head -n 1 || true)"
      if [[ -n "${ticket}" ]]; then
        echo "${line}  [${ticket}]"
      else
        echo "${line}"
      fi
    done