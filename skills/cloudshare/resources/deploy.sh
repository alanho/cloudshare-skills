#!/usr/bin/env bash
# deploy.sh — share a local file or directory.
#
# Usage: deploy.sh <path-to-file-or-dir>
#
# Generates a /r/<slug>/ path under the user's cloudshare project, with a unique
# token. Updates the local mirror, redeploys the project, and prints the URL.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${script_dir}/lib/auth.sh"

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"

# If config is missing, instruct the user to run setup in their own terminal.
# (The setup wizard is interactive and lives at the repo root, deliberately
# decoupled from any agent's skill install path.)
if ! cs_load_config 2>/dev/null; then
  cat >&2 <<'SETUP_REQUIRED'
✗ cloudshare is not set up yet. Run this once in your terminal:

  curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash

Then re-run this share command.
SETUP_REQUIRED
  exit 2
fi

input="${1:-}"
if [ -z "$input" ]; then
  echo "Usage: deploy.sh <path-to-file-or-dir>" >&2
  exit 1
fi

input=$(cd "$(dirname -- "$input")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename -- "$input")") || {
  echo "✗ Path not found: $1" >&2
  exit 1
}
[ -e "$input" ] || { echo "✗ Path does not exist: $input" >&2; exit 1; }

# Reject if too large (Cloudflare Pages: 100 MB per deploy total).
size_bytes=$(du -sb "$input" 2>/dev/null | awk '{print $1}' || du -sk "$input" | awk '{print $1*1024}')
if [ "${size_bytes:-0}" -gt $((90 * 1024 * 1024)) ]; then
  echo "✗ Source is larger than 90 MB. Cloudflare Pages caps at 100 MB per deploy." >&2
  exit 1
fi

mirror_dir="${cs_config_dir}/projects/${PROJECT_NAME}"
[ -d "$mirror_dir" ] || { echo "✗ Mirror missing: $mirror_dir. Re-run setup." >&2; exit 1; }

# Generate slug + token.
slug=$(bash "${script_dir}/slug.sh" path "$input")
token=$(openssl rand -hex 16)
share_dir="${mirror_dir}/r/${slug}"

# Stage content.
mkdir -p "$share_dir"
if [ -d "$input" ]; then
  rsync -a --delete "${input%/}/" "${share_dir}/"
  # ensure index.html exists for directories; if missing, generate a tiny listing
  if [ ! -f "${share_dir}/index.html" ]; then
    {
      echo "<!doctype html><html><body><ul>"
      find "${share_dir}" -maxdepth 1 -mindepth 1 -printf '<li><a href="./%P">%P</a></li>\n' 2>/dev/null \
        || (cd "${share_dir}" && for f in *; do printf '<li><a href="./%s">%s</a></li>\n' "$f" "$f"; done)
      echo "</ul></body></html>"
    } > "${share_dir}/index.html"
  fi
else
  filename=$(basename -- "$input")
  ext="${filename##*.}"
  ext_lower=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  case "$ext_lower" in
    html|htm)
      cp "$input" "${share_dir}/index.html"
      ;;
    *)
      cp "$input" "${share_dir}/${filename}"
      cat > "${share_dir}/index.html" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=./${filename}"></head>
<body><a href="./${filename}">View ${filename}</a></body></html>
HTML
      ;;
  esac
fi

# Update token map.
echo "→ Registering token..."
bash "${script_dir}/lib/tokens.sh" add "$slug" "$token"

# Redeploy mirror. cd into mirror so wrangler detects `functions/` for the
# Pages Functions middleware (token gate). Without this it silently skips.
echo "→ Deploying..."
( cd "${mirror_dir}" && \
  CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
  CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
    npx --yes wrangler@latest pages deploy . \
      --project-name "${PROJECT_NAME}" \
      --branch main \
      --commit-dirty=true >/dev/null )

# Build and emit URL.
share_url="https://${PROJECT_NAME}.pages.dev/r/${slug}/?token=${token}"

# Append to log.
log_file="${cs_config_dir}/shares.log"
printf '%s | %s | %s | %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$slug" "$input" "$token" >> "$log_file"
chmod 600 "$log_file" 2>/dev/null || true

# Copy to clipboard if possible.
clip_status="(no clipboard tool found)"
if bash "${script_dir}/lib/clipboard.sh" "$share_url" 2>/dev/null; then
  clip_status="(copied to clipboard)"
fi

# Output. The line starting with `URL: ` is the canonical one for the agent.
echo
echo "URL: ${share_url}"
echo
echo "✓ Shared: ${input}"
echo "  Slug:  ${slug}"
echo "  Open:  ${share_url}"
echo "  ${clip_status}"
echo
