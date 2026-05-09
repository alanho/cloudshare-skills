#!/usr/bin/env bash
# cloudshare setup — runs once to authenticate to Cloudflare, create the
# user's Pages project, initialize the local mirror, and save credentials to
# ~/.config/cloudshare/config.env.
#
# Designed to be run two ways:
#
#   1. Direct:  bash setup.sh
#   2. Curl pipe (no skill install needed):
#        curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
#
# Self-contained — embeds the page middleware, _headers, landing page, and a
# word list for slug suggestions. No reliance on sibling files.

set -euo pipefail

# Read prompts from /dev/tty so the script works under `curl ... | bash`
# (where stdin is the piped script, not the user's terminal).
if [ -e /dev/tty ]; then
  TTY=/dev/tty
else
  TTY=/dev/stdin
fi

# Helper: read a line from $TTY and strip surrounding whitespace + CR.
# Some terminals/clipboards leave \r or trailing spaces that break validation.
read_tty() {
  local _line
  IFS= read -r _line < "$TTY" || true
  _line="${_line%$'\r'}"           # strip trailing CR
  _line="${_line#"${_line%%[![:space:]]*}"}"  # ltrim
  _line="${_line%"${_line##*[![:space:]]}"}"  # rtrim
  printf '%s' "$_line"
}

# Helper: retry curl up to 3 times with brief backoff on connection errors.
# Surfaces the final error if all attempts fail.
cf_curl() {
  local attempt
  local out
  for attempt in 1 2 3; do
    if out=$(curl --connect-timeout 10 --max-time 30 -sS "$@" 2>&1); then
      printf '%s' "$out"
      return 0
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "  ⚠️  Cloudflare API request failed (attempt ${attempt}/3): $out" >&2
      sleep $((attempt * 2))
    fi
  done
  echo "✗ Cloudflare API unreachable after 3 attempts." >&2
  echo "  Last error: $out" >&2
  echo "  Check: VPN, DNS, firewall blocking api.cloudflare.com." >&2
  return 1
}

# Helper: returns 0 iff Cloudflare API response is JSON with success:true.
# Uses node (already required by `npx skills` and `npx wrangler`) so we
# get a real JSON parser instead of brittle regex over pretty-printed JSON.
cf_ok() {
  printf '%s' "$1" | node -e '
    try {
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      process.exit(d && d.success === true ? 0 : 1);
    } catch (e) { process.exit(1); }
  '
}

config_dir="${CLOUDSHARE_CONFIG_DIR:-$HOME/.config/cloudshare}"
config_file="${config_dir}/config.env"

cat <<'BANNER'

╭───────────────────────────────────────────────╮
│  cloudshare — first-run setup                 │
╰───────────────────────────────────────────────╯

This will:
  1. Authenticate you to Cloudflare
  2. Create a Cloudflare Pages project (your personal share domain)
  3. Save credentials to ~/.config/cloudshare/config.env (chmod 600)

Free Cloudflare account required: https://dash.cloudflare.com/sign-up

BANNER

# ── If config already exists, confirm before overwriting ──────────────────────
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  set -a; . "$config_file"; set +a
  if [ -n "${PROJECT_NAME:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "✓ cloudshare is already set up. Project: ${PROJECT_NAME}"
    echo "  Domain: https://${PROJECT_NAME}.pages.dev/"
    echo
    printf "Reconfigure from scratch? [y/N]: "
    ans=$(read_tty)
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Setup skipped."; exit 0; }
    rm -f "$config_file"
    unset PROJECT_NAME CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
  fi
fi

# ── Prerequisites ────────────────────────────────────────────────────────────
for cmd in curl openssl node; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "✗ Required: $cmd" >&2; exit 1; }
done

# ── Step 1: API token ────────────────────────────────────────────────────────
echo "Step 1/3: Cloudflare API token"
echo
echo "Create a custom token at:"
echo "  https://dash.cloudflare.com/profile/api-tokens"
echo "with these permissions:"
echo "  • Account → Cloudflare Pages → Edit"
echo "  • Account → Account Settings → Read"
echo
printf "Paste API token: "
stty -echo < "$TTY" 2>/dev/null || true
CLOUDFLARE_API_TOKEN=$(read_tty)
stty echo < "$TTY" 2>/dev/null || true
echo

verify_resp=$(cf_curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify) || exit 1
if ! cf_ok "$verify_resp"; then
  echo "✗ Token verification failed. Check the scopes and try again." >&2
  exit 1
fi
echo "✓ Token verified"
echo

# ── Step 2: Account ID ───────────────────────────────────────────────────────
echo "Step 2/3: Cloudflare Account"
echo
accounts_json=$(cf_curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/accounts) || exit 1

account_count=$(printf '%s' "$accounts_json" | node -e '
  const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
  process.stdout.write(String((d.result || []).length));
')

case "$account_count" in
  0)
    echo "✗ Token has no accessible accounts. Check token permissions." >&2
    exit 1
    ;;
  1)
    CLOUDFLARE_ACCOUNT_ID=$(printf '%s' "$accounts_json" | node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      process.stdout.write(d.result[0].id);
    ')
    account_name=$(printf '%s' "$accounts_json" | node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      process.stdout.write(d.result[0].name);
    ')
    echo "✓ Using account: ${account_name} (${CLOUDFLARE_ACCOUNT_ID})"
    ;;
  *)
    echo "Multiple accounts found:"
    printf '%s' "$accounts_json" | node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      d.result.forEach((a, i) => console.log(`  ${i+1}. ${a.name} (${a.id})`));
    '
    printf "Pick number: "
    pick=$(read_tty)
    CLOUDFLARE_ACCOUNT_ID=$(printf '%s' "$accounts_json" | node -e "
      const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      process.stdout.write(d.result[${pick}-1].id);
    ")
    ;;
esac
echo

# ── Step 3: Project name ─────────────────────────────────────────────────────
echo "Step 3/3: Pick your cloudshare subdomain"
echo

# Embedded word list for friendly slug suggestions.
ADJECTIVES="amber azure brave bright calm clever cosmic crimson crystal daring \
divine dreamy eager electric elegant ember emerald fancy fearless fierce flaming \
forest frosty gentle glacial gleaming golden graceful hazel honest icy indigo \
jade jolly jovial keen kind lavender lively loyal lucky lunar lush mellow merry \
mighty mint misty mystic noble ocean opal peachy plucky polar proud purple quick \
quiet radiant rosy royal ruby rugged sandy sapphire scarlet shadow silent silver \
sleek snowy solar splendid starlit stellar stoic stormy sturdy sunny swift tender \
topaz tranquil turquoise twilight valiant velvet vibrant violet vivid warm wild \
windy witty zealous zen zesty"

NOUNS="acorn arrow aspen badger bamboo banner bay beacon bear birch blossom brook \
canyon cedar cherry cliff cloud clover coast comet coral cottage cove crane creek \
cypress deer dolphin dove dune eagle elm fern field finch fir flame forest fox \
frost galaxy garden gem glade goose grove gull harbor hawk hazel heron hill horizon \
ibis iris ivy jasper juniper koala lake lark laurel leaf lemon lily lion lotus \
lynx maple meadow meteor mist moon moss nebula nest oak ocean opal orca otter owl \
panda peach pearl pebble pine plover pond poppy quail quartz rabbit rain raven \
reef ridge river robin rose seal shore sparrow spruce star stone stream sunset \
swan thistle tiger tide trout tulip valley violet willow wolf wren zebra"

suggest_slug() {
  local adj noun num
  adj=$(printf '%s\n' $ADJECTIVES | awk 'NF' | sort -R | head -n 1)
  noun=$(printf '%s\n' $NOUNS | awk 'NF' | sort -R | head -n 1)
  num=$(( RANDOM % 100 ))
  printf '%s-%s-%02d' "$adj" "$noun" "$num"
}

REUSE_EXISTING=0

while :; do
  suggested=$(suggest_slug)
  printf "Suggested: %s.pages.dev  [Enter to accept, or type your own]: " "$suggested"
  picked=$(read_tty)
  PROJECT_NAME="${picked:-$suggested}"

  # Validate name: lowercase alphanumeric + hyphens, 1-58 chars, no leading/trailing hyphen.
  if ! printf '%s' "$PROJECT_NAME" | grep -qE '^[a-z0-9]([a-z0-9-]{0,56}[a-z0-9])?$'; then
    echo "  ✗ Invalid: '${PROJECT_NAME}'. Use lowercase letters, digits, hyphens"
    echo "    (no leading/trailing hyphen, max 58 chars, no spaces or other chars)."
    continue
  fi

  # Cloudflare API returns 404 if the project doesn't exist (= available).
  status=$(curl --connect-timeout 10 --max-time 30 -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}" \
    2>/dev/null || echo "000")

  case "$status" in
    404) echo "  ✓ ${PROJECT_NAME}.pages.dev is available"; break ;;
    200)
      echo "  ⚠️  ${PROJECT_NAME} already exists in your account."
      printf "  Reuse it? [Y/n]: "
      ans=$(read_tty)
      if [ -z "$ans" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        REUSE_EXISTING=1
        break
      fi
      ;;
    000) echo "  ⚠️  Could not reach api.cloudflare.com (network / DNS / VPN issue). Retrying..."
         sleep 2 ;;
    *)   echo "  ✗ Cloudflare API returned HTTP $status. Try a different name." ;;
  esac
done
echo

# ── Create the Pages project (or skip if reusing existing) ───────────────────
if [ "$REUSE_EXISTING" -eq 1 ]; then
  echo "Reusing existing Cloudflare Pages project: ${PROJECT_NAME}"
else
  echo "Creating Cloudflare Pages project: ${PROJECT_NAME}..."
  create_payload=$(node -e "process.stdout.write(JSON.stringify({name: '${PROJECT_NAME}', production_branch: 'main'}))")
  create_resp=$(cf_curl -X POST \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$create_payload" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects") || exit 1
  if ! cf_ok "$create_resp"; then
    echo "✗ Failed to create project:" >&2
    printf '%s\n' "$create_resp" >&2
    exit 1
  fi
  echo "✓ Project created"
fi

# ── Initialize local mirror with embedded templates ──────────────────────────
mirror_dir="${config_dir}/projects/${PROJECT_NAME}"
mkdir -p "${mirror_dir}/r" "${mirror_dir}/functions"

cat > "${mirror_dir}/_headers" <<'HEADERS'
/*
  Referrer-Policy: no-referrer
  X-Robots-Tag: noindex, nofollow
  X-Content-Type-Options: nosniff
HEADERS

cat > "${mirror_dir}/functions/_middleware.js" <<'MIDDLEWARE'
// cloudshare token gate.
// Validates ?token=<x> against SHARE_TOKENS_JSON env var, keyed by /r/<slug>/.

export async function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  if (path === '/' || path === '/index.html' || path === '/favicon.ico' || path === '/robots.txt') {
    return context.next();
  }

  const m = path.match(/^\/r\/([^/]+)(\/.*)?$/);
  if (!m) {
    return new Response('Not Found', { status: 404 });
  }

  const slug = m[1];
  let tokens = {};
  try {
    tokens = JSON.parse(context.env.SHARE_TOKENS_JSON || '{}');
  } catch (e) {
    return new Response('Server misconfiguration', { status: 500 });
  }

  const expected = tokens[slug];
  if (!expected) {
    return new Response('Not Found', { status: 404 });
  }

  const provided = url.searchParams.get('token');
  if (provided !== expected) {
    return new Response('Unauthorized — link requires a valid token.', {
      status: 401,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }

  return context.next();
}
MIDDLEWARE

cat > "${mirror_dir}/index.html" <<'LANDING'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>cloudshare</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; background: #0f172a; color: #94a3b8; margin: 0; padding: 80px 20px; text-align: center; }
  h1 { font-size: 1.5rem; color: #e2e8f0; margin: 0 0 8px; font-weight: 600; }
  p { font-size: 0.95rem; max-width: 480px; margin: 0 auto; line-height: 1.5; }
  code { background: #1e293b; color: #22d3ee; padding: 2px 6px; border-radius: 4px; font-size: 0.85em; }
  a { color: #22d3ee; text-decoration: none; }
</style>
</head>
<body>
  <h1>cloudshare</h1>
  <p>Nothing to see here. Shared files live at <code>/r/&lt;slug&gt;/?token=…</code> — open the specific link your friend sent you.</p>
  <p style="margin-top: 32px; font-size: 0.8rem; opacity: 0.6;">Powered by <a href="https://github.com/alanho/cloudshare-skills">cloudshare-skills</a></p>
</body>
</html>
LANDING

# ── Save config ──────────────────────────────────────────────────────────────
mkdir -p "$config_dir"
umask 077
cat > "$config_file" <<EOF
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
EOF
chmod 600 "$config_file"

# ── Initialize SHARE_TOKENS_JSON env var on the project ──────────────────────
echo "Initializing SHARE_TOKENS_JSON..."
init_payload=$(node -e '
  const body = {
    deployment_configs: {
      production: { env_vars: { SHARE_TOKENS_JSON: { type: "plain_text", value: "{}" } } }
    }
  };
  process.stdout.write(JSON.stringify(body));
')
patch_resp=$(cf_curl -X PATCH \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$init_payload" \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}") || exit 1
if ! cf_ok "$patch_resp"; then
  echo "⚠️  Warning: failed to set SHARE_TOKENS_JSON env var; continuing anyway." >&2
  printf '%s\n' "$patch_resp" >&2
fi

# ── First deploy ─────────────────────────────────────────────────────────────
echo "Deploying initial mirror..."
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
  npx --yes wrangler@latest pages deploy "${mirror_dir}" \
    --project-name "${PROJECT_NAME}" \
    --branch main \
    --commit-dirty=true >/dev/null

# ── Append marker to share log ───────────────────────────────────────────────
log_file="${config_dir}/shares.log"
mkdir -p "$config_dir"
printf '# %s | setup-complete | project=%s | domain=https://%s.pages.dev/\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_NAME" "$PROJECT_NAME" >> "$log_file"
chmod 600 "$log_file" 2>/dev/null || true

cat <<DONE

✓ Setup complete!

  Domain:  https://${PROJECT_NAME}.pages.dev/
  Config:  ${config_file}
  Mirror:  ${mirror_dir}

Now ask your agent to share a file — for example:
  "share this file: ~/Downloads/photo.png"

DONE
