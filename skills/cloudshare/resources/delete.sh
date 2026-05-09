#!/usr/bin/env bash
# delete.sh — delete one share by slug.
#
# Usage: delete.sh <slug>

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${script_dir}/lib/auth.sh"

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"

if ! cs_load_config 2>/dev/null; then
  cat >&2 <<'SETUP_REQUIRED'
✗ cloudshare is not set up yet. Run this once in your terminal:

  curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
SETUP_REQUIRED
  exit 2
fi

slug="${1:-}"
if [ -z "$slug" ]; then
  echo "Usage: delete.sh <slug>" >&2
  exit 1
fi

mirror_dir="${cs_config_dir}/projects/${PROJECT_NAME}"
share_dir="${mirror_dir}/r/${slug}"

if [ ! -d "$share_dir" ]; then
  echo "✗ Slug not found in local mirror: $slug" >&2
  exit 1
fi

echo "→ Removing local mirror entry..."
rm -rf "$share_dir"

echo "→ Removing token from CF env var..."
bash "${script_dir}/lib/tokens.sh" remove "$slug"

echo "→ Redeploying..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
  npx --yes wrangler@latest pages deploy "${mirror_dir}" \
    --project-name "${PROJECT_NAME}" \
    --branch main \
    --commit-dirty=true >/dev/null

# Mark as deleted in log.
log_file="${cs_config_dir}/shares.log"
printf '# %s | deleted | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$slug" >> "$log_file"

echo "✓ Deleted: $slug"
