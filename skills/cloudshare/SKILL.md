---
name: cloudshare
description: Upload a local HTML file, image, PDF, or directory to Cloudflare
  Pages and return a token-protected shareable URL on the user's personal
  cloudshare subdomain (e.g. purple-tiger-42.pages.dev/r/<slug>/?token=<x>).
  On first use, walks the user through Cloudflare account creation, API auth
  setup, and choosing a personal subdomain; subsequent runs deploy with one
  command. Trigger when the user asks to "share this file", "publish this
  html", "make a shareable link", "upload to cloudflare", or invokes
  /cloudshare. Also use when the user wants to list past shares, delete a
  share, or rotate a share's token.
---

# cloudshare

Share a local file (HTML, image, PDF, or directory) as a token-gated URL on
the user's personal Cloudflare Pages subdomain.

## When to use this skill

- User asks to share a local file or directory
- User wants a private link with token gating
- User mentions "Cloudflare Pages", "shareable URL", or "publish this"
- User asks to manage past shares: list, delete, rotate token

## Architecture (one-liner)

One Cloudflare Pages project per user (chosen at first-run). Each share lands
at `/r/<slug>/` under that project, with its own random token stored in the
project's `SHARE_TOKENS_JSON` env var. Middleware validates the token before
serving any path under `/r/`.

## Companion scripts (in this skill's `resources/` dir)

- `resources/setup.sh` — first-run wizard
- `resources/deploy.sh` — share a file or directory
- `resources/list.sh` — list past shares
- `resources/delete.sh` — delete one share
- `resources/rotate.sh` — rotate token on one share
- `resources/lib/{auth,tokens,clipboard}.sh` — helpers
- `resources/template/` — `_headers`, `functions/_middleware.js`, landing `index.html`

When invoking these scripts, the agent should always use the absolute path of
the skill directory (typically `~/.claude/skills/cloudshare/resources/...`).

## Prerequisites check

Run these checks first; abort with a clear message if anything is missing:

```bash
command -v openssl >/dev/null   || { echo "openssl required"; exit 1; }
command -v node    >/dev/null   || { echo "node required (https://nodejs.org/)"; exit 1; }
command -v curl    >/dev/null   || { echo "curl required"; exit 1; }
```

`wrangler` is invoked via `npx wrangler@latest` — no global install needed.

## First-run setup

Check whether `~/.config/cloudshare/config.env` exists and has all of
`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `PROJECT_NAME`. If not,
delegate to the setup wizard:

```bash
bash <SKILL_DIR>/resources/setup.sh
```

The wizard:
1. Prompts the user to create or sign into a free Cloudflare account.
2. Walks through creating a custom API token with two scopes:
   - `Account: Cloudflare Pages: Edit`
   - `Account: Account Settings: Read`
3. Verifies the token via the Cloudflare API.
4. Auto-resolves Account ID (or prompts to pick if multiple).
5. Suggests a friendly subdomain (adjective-noun-NN) and lets the user accept or override.
6. Validates the project name (lowercase alphanumeric + hyphens, ≤58 chars) and global uniqueness.
7. Creates the Pages project, initializes the local mirror, sets `SHARE_TOKENS_JSON='{}'`, and does an initial deploy.
8. Saves credentials to `~/.config/cloudshare/config.env` with `chmod 600`.

The wizard is interactive — relay any prompts directly to the user.

## Share workflow

For a single share, call:

```bash
bash <SKILL_DIR>/resources/deploy.sh <absolute-path-to-file-or-dir>
```

The script will:
1. Run setup if needed.
2. Generate a slug from the filename (e.g. `trip-options-9f3a`).
3. Generate a 32-hex-char token.
4. Stage the content into the local mirror at
   `~/.config/cloudshare/projects/<project>/r/<slug>/`.
5. Update `SHARE_TOKENS_JSON` via the Cloudflare API.
6. Redeploy the whole mirror via `npx wrangler@latest pages deploy`.
7. Print **the canonical URL on a single line starting with `URL: `** so the
   agent can extract it reliably:
   ```
   URL: https://<project>.pages.dev/r/<slug>/?token=<hex>
   ```
8. Copy the URL to the clipboard.
9. Append a row to `~/.config/cloudshare/shares.log`.

After running, present the URL prominently to the user. Mention the clipboard
copy. Note that **anyone with the URL has access** — treat it like a password.

## Subcommands

```bash
# List all past shares (slug, timestamp, URL)
bash <SKILL_DIR>/resources/list.sh

# Delete one share (revokes its URL, leaves others untouched)
bash <SKILL_DIR>/resources/delete.sh <slug>

# Rotate the token on one share (old token → 401, new URL printed)
bash <SKILL_DIR>/resources/rotate.sh <slug>
```

## Output format

When emitting a URL to the user, lead with the URL on its own line, then a
short success block. Example:

```
https://purple-tiger-42.pages.dev/r/trip-options-9f3a/?token=4b7c8d2e1a9f1234

✓ Shared `trip-options.html` (copied to clipboard).
```

## Limits and security

- Cloudflare Pages free tier: 500 deploys / month, 25 MB / file, 100 MB / deploy total.
- Each share is gated by a unique random token in the URL query string.
- `Referrer-Policy: no-referrer` is set, so most browsers won't leak the token via Referer.
- Whoever has the URL has access. The link **is** the credential.
- To revoke: `delete.sh <slug>` (URL → 404) or `rotate.sh <slug>` (URL → 401, new URL printed).

## Common failure modes

- **Token verification fails during setup** → user pasted a token without correct scopes; instruct them to recreate at https://dash.cloudflare.com/profile/api-tokens.
- **Project name taken** → wizard loops, ask user for a different name.
- **Source > 90 MB** → Cloudflare's per-deploy limit. Ask user to slim the input.
- **`SHARE_TOKENS_JSON` env var update returns 5xx** → Cloudflare API hiccup; retry once before surfacing.
- **`wrangler pages deploy` fails** → check that the API token has `Cloudflare Pages: Edit`, not just Read.
