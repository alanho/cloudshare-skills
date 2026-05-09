---
name: cloudshare
description: Upload a local HTML file, image, PDF, or directory to Cloudflare
  Pages and return a token-protected shareable URL on the user's personal
  cloudshare subdomain (e.g. purple-tiger-42.pages.dev/r/<slug>/?token=<x>).
  If the user has not yet set up cloudshare, instruct them to run a one-time
  setup command in their terminal — the setup wizard is interactive and must
  be run by the user, not the agent. Trigger when the user asks to "share this
  file", "publish this html", "make a shareable link", "upload to cloudflare",
  or invokes /cloudshare. Also use when the user wants to list past shares,
  delete a share, or rotate a share's token.
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

One Cloudflare Pages project per user (chosen at first-run setup). Each share
lands at `/r/<slug>/` under that project, with its own random token stored in
the project's `SHARE_TOKENS_JSON` env var. Middleware validates the token
before serving any path under `/r/`.

## Companion scripts (in this skill's `resources/` dir)

- `resources/deploy.sh` — share a file or directory
- `resources/list.sh` — list past shares
- `resources/delete.sh` — delete one share
- `resources/rotate.sh` — rotate token on one share
- `resources/lib/{auth,tokens,clipboard}.sh` — helpers
- `resources/template/` — reference templates (already copied into user's mirror at setup time)

When invoking these scripts, use the absolute path of the skill directory.
Different agents place skills in different locations — locate this SKILL.md
file and resolve relative paths from its directory.

## First-run setup is run by the user, not the agent

The setup wizard is **interactive** (token paste, account selection, project
name pick) and lives at the repo root, **decoupled from the skill install
path**. Do not try to run it from inside the agent — it requires a real TTY.

If `~/.config/cloudshare/config.env` does not exist (the share scripts will
return exit code 2 with a clear message), tell the user to paste this into
their terminal:

```
curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
```

The setup script will:
1. Prompt for a Cloudflare API token (custom token with `Account: Cloudflare Pages: Edit` + `Account: Account Settings: Read`).
2. Detect the account (or prompt to pick if multiple).
3. Suggest a friendly subdomain (e.g. `purple-tiger-42`); user can accept or override.
4. Create the Cloudflare Pages project, initialize the local mirror at `~/.config/cloudshare/projects/<name>/`, and set `SHARE_TOKENS_JSON='{}'`.
5. Save credentials to `~/.config/cloudshare/config.env` (chmod 600).

After setup, all shares from any agent (Claude Code, Codex, OpenCode, etc.)
read the same `~/.config/cloudshare/config.env` and target the same project.

## Prerequisites check

Before invoking any share script, optionally verify:

```bash
command -v openssl >/dev/null   || { echo "openssl required"; exit 1; }
command -v node    >/dev/null   || { echo "node required (https://nodejs.org/)"; exit 1; }
command -v curl    >/dev/null   || { echo "curl required"; exit 1; }
```

`wrangler` is invoked via `npx wrangler@latest` — no global install needed.

## Share workflow

```bash
bash <SKILL_DIR>/resources/deploy.sh <absolute-path-to-file-or-dir>
```

The script:
1. Loads config from `~/.config/cloudshare/config.env`.
2. If config missing, exits 2 with a setup instruction. **Relay the setup
   command verbatim to the user.**
3. Generates a slug from the filename (e.g. `trip-options-9f3a`).
4. Generates a 32-hex-char token.
5. Stages content into the local mirror.
6. Updates `SHARE_TOKENS_JSON` via the Cloudflare API.
7. Redeploys via `npx wrangler@latest pages deploy`.
8. Prints the canonical URL on a single line starting with `URL: `:
   ```
   URL: https://<project>.pages.dev/r/<slug>/?token=<hex>
   ```
9. Copies URL to clipboard.
10. Appends to `~/.config/cloudshare/shares.log`.

After running, present the URL prominently. Mention the clipboard copy. Note
that **anyone with the URL has access** — treat it like a password.

## Subcommands

```bash
bash <SKILL_DIR>/resources/list.sh                # list past shares
bash <SKILL_DIR>/resources/delete.sh <slug>       # revoke + delete a share
bash <SKILL_DIR>/resources/rotate.sh <slug>       # rotate token; old → 401
```

All three exit 2 with the same setup instruction if config is missing.

## Output format

Lead with the URL on its own line, then a short success block. Example:

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

- **Scripts exit 2 with "not set up yet"** → user has not run the curl-pipe setup. Ask them to.
- **Token verification fails during setup** → user pasted a token without correct scopes; instruct them to recreate at https://dash.cloudflare.com/profile/api-tokens.
- **Project name taken** → wizard loops, ask user for a different name.
- **Source > 90 MB** → Cloudflare's per-deploy limit. Ask user to slim the input.
- **`SHARE_TOKENS_JSON` env var update returns 5xx** → Cloudflare API hiccup; retry once before surfacing.
- **`wrangler pages deploy` fails** → check that the API token has `Cloudflare Pages: Edit`, not just Read.
