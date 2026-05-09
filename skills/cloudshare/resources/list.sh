#!/usr/bin/env bash
# list.sh — list past shares from ~/.config/cloudshare/shares.log.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${script_dir}/lib/auth.sh"

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"
log_file="${cs_config_dir}/shares.log"

if ! cs_load_config 2>/dev/null; then
  echo "✗ Not set up yet. Run setup first." >&2
  exit 1
fi

if [ ! -s "$log_file" ]; then
  echo "(no shares yet)"
  exit 0
fi

printf '%-22s  %-32s  %s\n' "WHEN" "SLUG" "URL"
printf '%-22s  %-32s  %s\n' "----" "----" "---"

# Track deleted slugs to skip them.
deleted=$(grep -E '^# .*deleted' "$log_file" 2>/dev/null | awk '{print $NF}' | sort -u)

while IFS='|' read -r ts slug src token; do
  ts=$(printf '%s' "$ts" | xargs)
  slug=$(printf '%s' "$slug" | xargs)
  [ -z "$slug" ] && continue
  [ "${slug:0:1}" = "#" ] && continue
  echo "$deleted" | grep -qx "$slug" && continue

  printf '%-22s  %-32s  https://%s.pages.dev/r/%s/?token=%s\n' \
    "$ts" "$slug" "$PROJECT_NAME" "$slug" "$(printf '%s' "$token" | xargs)"
done < "$log_file"
