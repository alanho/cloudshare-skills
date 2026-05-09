#!/usr/bin/env bash
# tokens.sh — read/write the SHARE_TOKENS_JSON env var on the Cloudflare Pages project.
#
# Subcommands:
#   tokens.sh get
#   tokens.sh add <slug> <token>
#   tokens.sh remove <slug>
#   tokens.sh rotate <slug> <new-token>
#
# Requires: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, PROJECT_NAME exported.
# Uses node for JSON manipulation (always available since installer requires node for skills CLI).

set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?must be set}"
: "${CLOUDFLARE_ACCOUNT_ID:?must be set}"
: "${PROJECT_NAME:?must be set}"

CF_API="https://api.cloudflare.com/client/v4"
PROJECT_URL="${CF_API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}"

cmd="${1:-}"

# Fetch the SHARE_TOKENS_JSON value as a JSON string (or {} if unset).
fetch_tokens_json() {
  local resp
  resp=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              "$PROJECT_URL")
  printf '%s' "$resp" | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (!data.success) {
      process.stderr.write("Cloudflare API error: " + JSON.stringify(data.errors || data) + "\n");
      process.exit(1);
    }
    const env = ((data.result || {}).deployment_configs || {}).production || {};
    const ev = env.env_vars || {};
    const tok = ev.SHARE_TOKENS_JSON;
    if (!tok || !tok.value) { process.stdout.write("{}"); return; }
    try {
      JSON.parse(tok.value);
      process.stdout.write(tok.value);
    } catch (e) {
      process.stdout.write("{}");
    }
  '
}

# Patch the env var with new JSON. Argument: JSON string.
patch_tokens_json() {
  local new_json="$1"
  local payload
  payload=$(node -e '
    const v = process.argv[1];
    JSON.parse(v); // validate
    const body = {
      deployment_configs: {
        production: { env_vars: { SHARE_TOKENS_JSON: { type: "plain_text", value: v } } }
      }
    };
    process.stdout.write(JSON.stringify(body));
  ' "$new_json")

  local resp
  resp=$(curl -sS -X PATCH \
              -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              -d "$payload" \
              "$PROJECT_URL")

  printf '%s' "$resp" | node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (!d.success) {
      process.stderr.write("Cloudflare API error: " + JSON.stringify(d.errors || d) + "\n");
      process.exit(1);
    }
  '
}

case "$cmd" in
  get)
    fetch_tokens_json
    echo
    ;;

  add)
    slug="${2:?slug required}"
    tok="${3:?token required}"
    current=$(fetch_tokens_json)
    new=$(node -e '
      const cur = JSON.parse(process.argv[1] || "{}");
      cur[process.argv[2]] = process.argv[3];
      process.stdout.write(JSON.stringify(cur));
    ' "$current" "$slug" "$tok")
    patch_tokens_json "$new"
    ;;

  remove)
    slug="${2:?slug required}"
    current=$(fetch_tokens_json)
    new=$(node -e '
      const cur = JSON.parse(process.argv[1] || "{}");
      delete cur[process.argv[2]];
      process.stdout.write(JSON.stringify(cur));
    ' "$current" "$slug")
    patch_tokens_json "$new"
    ;;

  rotate)
    slug="${2:?slug required}"
    new_tok="${3:?new token required}"
    current=$(fetch_tokens_json)
    new=$(node -e '
      const cur = JSON.parse(process.argv[1] || "{}");
      if (!(process.argv[2] in cur)) {
        process.stderr.write("slug not found: " + process.argv[2] + "\n");
        process.exit(1);
      }
      cur[process.argv[2]] = process.argv[3];
      process.stdout.write(JSON.stringify(cur));
    ' "$current" "$slug" "$new_tok")
    patch_tokens_json "$new"
    ;;

  init)
    # idempotent: ensure the env var exists with at least {}.
    current=$(fetch_tokens_json)
    if [ "$current" = "{}" ]; then
      patch_tokens_json "{}"
    fi
    ;;

  *)
    cat <<'EOF' >&2
Usage:
  tokens.sh get
  tokens.sh add <slug> <token>
  tokens.sh remove <slug>
  tokens.sh rotate <slug> <new-token>
  tokens.sh init
EOF
    exit 1
    ;;
esac
