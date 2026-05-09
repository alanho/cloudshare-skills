#!/usr/bin/env bash
# clipboard.sh — copy stdin to system clipboard. Cross-OS detection.
# Usage: echo "text" | bash clipboard.sh
#        bash clipboard.sh "text"

set -euo pipefail

cs_copy() {
  local data="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$data" | pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$data" | wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$data" | xclip -selection clipboard
  elif command -v xsel >/dev/null 2>&1; then
    printf '%s' "$data" | xsel --clipboard --input
  elif command -v clip.exe >/dev/null 2>&1; then
    printf '%s' "$data" | clip.exe
  else
    return 1
  fi
}

if [ $# -gt 0 ]; then
  cs_copy "$1"
else
  cs_copy "$(cat)"
fi
