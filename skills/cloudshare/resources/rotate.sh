#!/usr/bin/env bash
# rotate.sh — rotate the token on a single share.
#
# Usage: rotate.sh <slug>

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
  echo "Usage: rotate.sh <slug>" >&2
  exit 1
fi

mirror_dir="${cs_config_dir}/projects/${PROJECT_NAME}"
[ -d "${mirror_dir}/r/${slug}" ] || { echo "✗ Slug not found: $slug" >&2; exit 1; }

new_token=$(openssl rand -hex 16)

echo "→ Updating token map..."
bash "${script_dir}/lib/tokens.sh" rotate "$slug" "$new_token"

echo "→ Redeploying..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
  npx --yes wrangler@latest pages deploy "${mirror_dir}" \
    --project-name "${PROJECT_NAME}" \
    --branch main \
    --commit-dirty=true >/dev/null

new_url="https://${PROJECT_NAME}.pages.dev/r/${slug}/?token=${new_token}"

# Append to log so list.sh shows the new token.
log_file="${cs_config_dir}/shares.log"
printf '%s | %s | (rotated) | %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$slug" "$new_token" >> "$log_file"

# Copy to clipboard.
clip_status="(no clipboard tool found)"
if bash "${script_dir}/lib/clipboard.sh" "$new_url" 2>/dev/null; then
  clip_status="(copied to clipboard)"
fi

echo
echo "URL: ${new_url}"
echo
echo "✓ Rotated token for: ${slug}"
echo "  ${clip_status}"
echo "  Old links with the previous token now return 401."
