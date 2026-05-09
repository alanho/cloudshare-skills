#!/usr/bin/env bash
# auth.sh — load cloudshare credentials from ~/.config/cloudshare/config.env.
# Source this file; it exports CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, PROJECT_NAME.
# Returns non-zero (when sourced) if config is missing or incomplete.

cs_config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"
cs_config_file="${cs_config_dir}/config.env"

cs_load_config() {
  if [ ! -f "$cs_config_file" ]; then
    return 1
  fi
  # shellcheck disable=SC1090
  set -a; . "$cs_config_file"; set +a
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || return 2
  [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || return 3
  [ -n "${PROJECT_NAME:-}" ] || return 4
  return 0
}

cs_save_config() {
  mkdir -p "$cs_config_dir"
  umask 077
  cat > "$cs_config_file" <<EOF
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
EOF
  chmod 600 "$cs_config_file"
}

# Helper: verify an API token via Cloudflare API.
# Usage: cs_verify_token <token>
cs_verify_token() {
  local tok="$1"
  curl -sS -H "Authorization: Bearer $tok" \
    https://api.cloudflare.com/client/v4/user/tokens/verify \
    | node -e '
        try {
          const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
          process.exit(d && d.success === true ? 0 : 1);
        } catch (e) { process.exit(1); }
      '
}

# Helper: list accounts the token can access.
# Echoes JSON of accounts array.
cs_list_accounts() {
  local tok="$1"
  curl -sS -H "Authorization: Bearer $tok" \
    https://api.cloudflare.com/client/v4/accounts
}

# Auto-load on source unless caller asks otherwise.
if [ "${CLOUDSHARE_NO_AUTOLOAD:-0}" != "1" ]; then
  cs_load_config || true
fi
