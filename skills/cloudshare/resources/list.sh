#!/usr/bin/env bash
# list.sh — list past shares from ~/.config/cloudshare/shares.log.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${script_dir}/lib/auth.sh"

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"
log_file="${cs_config_dir}/shares.log"

if ! cs_load_config 2>/dev/null; then
  cat >&2 <<'SETUP_REQUIRED'
✗ cloudshare is not set up yet. Run this once in your terminal:

  curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
SETUP_REQUIRED
  exit 2
fi

if [ ! -s "$log_file" ]; then
  echo "(no shares yet)"
  exit 0
fi

printf '%-22s  %-32s  %s\n' "WHEN" "SLUG" "URL"
printf '%-22s  %-32s  %s\n' "----" "----" "---"

# Track deleted slugs to skip them. `|| true` because grep returns 1 when
# there are no matches yet, which `set -e` + `pipefail` would treat as fatal.
deleted=$(grep -E '^# .*deleted' "$log_file" 2>/dev/null | awk '{print $NF}' | sort -u || true)

while IFS='|' read -r ts slug src token; do
  ts=$(printf '%s' "$ts" | xargs)
  slug=$(printf '%s' "$slug" | xargs)
  # Skip empty lines and `#`-prefixed marker lines (setup-complete, deleted, etc.)
  [ -z "$slug" ] && continue
  [ "${ts:0:1}" = "#" ] && continue
  # Skip slugs that have been deleted.
  if [ -n "$deleted" ] && printf '%s\n' "$deleted" | grep -qx "$slug"; then
    continue
  fi

  printf '%-22s  %-32s  https://%s.pages.dev/r/%s/?token=%s\n' \
    "$ts" "$slug" "$PROJECT_NAME" "$slug" "$(printf '%s' "$token" | xargs)"
done < "$log_file"
