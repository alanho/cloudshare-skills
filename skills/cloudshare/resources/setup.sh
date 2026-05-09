#!/usr/bin/env bash
# setup.sh — first-run wizard for cloudshare.
# Sets up Cloudflare auth, picks a project subdomain, creates the Pages project,
# initializes the local mirror, and writes ~/.config/cloudshare/config.env.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${script_dir}/lib/auth.sh"

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"

# If config is already complete, no-op.
if cs_load_config 2>/dev/null; then
  echo "✓ cloudshare already set up. Project: ${PROJECT_NAME}"
  echo "  Domain: https://${PROJECT_NAME}.pages.dev/"
  echo "  Re-run setup explicitly with --force to reconfigure."
  if [ "${1:-}" != "--force" ]; then
    exit 0
  fi
fi

cat <<'BANNER'

╭───────────────────────────────────────────────╮
│  cloudshare — first-run setup                 │
╰───────────────────────────────────────────────╯

This will:
  1. Authenticate you to Cloudflare
  2. Create a new Cloudflare Pages project (your personal share domain)
  3. Save credentials locally to ~/.config/cloudshare/config.env (chmod 600)

You'll need a free Cloudflare account: https://dash.cloudflare.com/sign-up

BANNER

# ── Step 1: API token ────────────────────────────────────────────────────────
echo "Step 1/3: Cloudflare API token"
echo
echo "Create a custom token at:"
echo "  https://dash.cloudflare.com/profile/api-tokens"
echo "with permissions:"
echo "  • Account: Cloudflare Pages: Edit"
echo "  • Account: Account Settings: Read"
echo
printf "Paste API token: "
stty -echo 2>/dev/null || true
read -r CLOUDFLARE_API_TOKEN
stty echo 2>/dev/null || true
echo

if ! cs_verify_token "$CLOUDFLARE_API_TOKEN"; then
  echo "✗ Token verification failed. Check token scopes and try again." >&2
  exit 1
fi
echo "✓ Token verified"
echo

# ── Step 2: Account ID ───────────────────────────────────────────────────────
echo "Step 2/3: Cloudflare Account"
echo
accounts_json=$(cs_list_accounts "$CLOUDFLARE_API_TOKEN")
account_count=$(printf '%s' "$accounts_json" | node -e '
  const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
  process.stdout.write(String((d.result || []).length));
')

if [ "$account_count" = "1" ]; then
  CLOUDFLARE_ACCOUNT_ID=$(printf '%s' "$accounts_json" | node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    process.stdout.write(d.result[0].id);
  ')
  account_name=$(printf '%s' "$accounts_json" | node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    process.stdout.write(d.result[0].name);
  ')
  echo "✓ Using account: ${account_name} (${CLOUDFLARE_ACCOUNT_ID})"
elif [ "$account_count" = "0" ]; then
  echo "✗ Token has no accessible accounts. Check token permissions." >&2
  exit 1
else
  echo "Multiple accounts found:"
  printf '%s' "$accounts_json" | node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    d.result.forEach((a, i) => console.log(`  ${i+1}. ${a.name} (${a.id})`));
  '
  printf "Pick number: "
  read -r pick
  CLOUDFLARE_ACCOUNT_ID=$(printf '%s' "$accounts_json" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    process.stdout.write(d.result[${pick}-1].id);
  ")
fi
echo

# ── Step 3: Project name ─────────────────────────────────────────────────────
echo "Step 3/3: Pick your cloudshare subdomain"
echo

# Loop until we find an available name.
while :; do
  suggested=$(bash "${script_dir}/slug.sh" project)
  printf "Suggested: %s.pages.dev  [Enter to accept, or type your own]: " "$suggested"
  read -r picked
  PROJECT_NAME="${picked:-$suggested}"

  # Validate against Cloudflare Pages naming rules:
  # lowercase alphanumeric and hyphens, 1-58 chars, no leading/trailing hyphen.
  if ! printf '%s' "$PROJECT_NAME" | grep -qE '^[a-z0-9]([a-z0-9-]{0,56}[a-z0-9])?$'; then
    echo "  ✗ Invalid name. Use lowercase letters, digits, hyphens (no leading/trailing hyphen, max 58 chars)."
    continue
  fi

  # Check global uniqueness.
  status=$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}")

  case "$status" in
    404) echo "  ✓ ${PROJECT_NAME}.pages.dev is available"; break ;;
    200) echo "  ✗ ${PROJECT_NAME} is already taken (in your account). Try a different name." ;;
    *)   echo "  ✗ Cloudflare API returned $status. Try a different name." ;;
  esac
done
echo

# ── Create project ───────────────────────────────────────────────────────────
echo "Creating Cloudflare Pages project: ${PROJECT_NAME}..."
create_resp=$(curl -sS -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(node -e "process.stdout.write(JSON.stringify({name: '${PROJECT_NAME}', production_branch: 'main'}))")" \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects")

if ! printf '%s' "$create_resp" | grep -q '"success":true'; then
  echo "✗ Failed to create project:" >&2
  printf '%s\n' "$create_resp" >&2
  exit 1
fi
echo "✓ Project created"

# ── Initialize local mirror ──────────────────────────────────────────────────
mirror_dir="${cs_config_dir}/projects/${PROJECT_NAME}"
mkdir -p "${mirror_dir}/r" "${mirror_dir}/functions"

cp "${script_dir}/template/_headers"                "${mirror_dir}/_headers"
cp "${script_dir}/template/functions/_middleware.js" "${mirror_dir}/functions/_middleware.js"
cp "${script_dir}/template/index.html"               "${mirror_dir}/index.html"

# Save config now so subsequent commands can use it.
export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID PROJECT_NAME
cs_save_config

# ── Initialize SHARE_TOKENS_JSON env var ─────────────────────────────────────
echo "Initializing SHARE_TOKENS_JSON env var..."
bash "${script_dir}/lib/tokens.sh" init

# ── First deploy ─────────────────────────────────────────────────────────────
echo "Deploying initial mirror..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
  npx --yes wrangler@latest pages deploy "${mirror_dir}" \
    --project-name "${PROJECT_NAME}" \
    --branch main \
    --commit-dirty=true >/dev/null

# Append a marker to the share log.
log_file="${cs_config_dir}/shares.log"
mkdir -p "$cs_config_dir"
printf '# %s | setup-complete | project=%s | domain=https://%s.pages.dev/\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "$PROJECT_NAME" >> "$log_file"
chmod 600 "$log_file" 2>/dev/null || true

cat <<DONE

✓ Setup complete!

  Domain:  https://${PROJECT_NAME}.pages.dev/
  Config:  ${cs_config_file}
  Mirror:  ${mirror_dir}

You can now share files with: cloudshare deploy <path>

DONE
