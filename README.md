# cloudshare-skills

Agent skill that uploads a local file (HTML, image, PDF, directory) to Cloudflare Pages and returns a token-protected shareable URL.

One stable, friendly subdomain per user (e.g. `purple-tiger-42.pages.dev`). Every subsequent share = a new path under that domain with its own token.

```
https://purple-tiger-42.pages.dev/r/trip-options-9f3a/?token=4b7c8d2e1a9f
                                   └─ filename slug + 4-char suffix
                                   └─ per-path token, server-side lookup
```

## Install

Two steps: install the skill into your agent(s), then run setup once.

```bash
# 1. Install the skill (works for Claude Code, Codex, OpenCode, +50 more)
npx skills add alanho/cloudshare-skills

# 2. Run the one-time setup (interactive — paste token, pick domain)
curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
```

Or in one line:

```bash
npx skills add alanho/cloudshare-skills && \
  curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
```

Why two steps? `npx skills` only copies files; it has no post-install hooks.
The setup wizard is interactive and writes credentials to a fixed path
(`~/.config/cloudshare/config.env`), so it must run separately in your
terminal. After that, every agent that has the skill installed reads the same
config.

To target a specific agent:

```bash
npx skills add alanho/cloudshare-skills -a claude-code
npx skills add alanho/cloudshare-skills -a codex
npx skills add alanho/cloudshare-skills -a opencode
```

## First-run setup (~3 min)

The setup wizard walks you through:

1. Creating a Cloudflare account (free) at https://dash.cloudflare.com/sign-up if you don't have one.
2. Pasting a custom API token from https://dash.cloudflare.com/profile/api-tokens with permissions:
   - `Account: Cloudflare Pages: Edit`
   - `Account: Account Settings: Read`
3. Picking your personal `cloudshare` subdomain. The wizard suggests something like `purple-tiger-42`; accept with Enter or type your own.

Credentials and project name are saved to `~/.config/cloudshare/config.env` (chmod 600). Re-run setup any time to reconfigure.

## Usage

Trigger by asking the agent:

- "share this file"
- "publish this html"
- "make a shareable link"
- "upload to cloudflare"
- `/cloudshare`

The skill calls `bash ./resources/deploy.sh <path-to-file-or-dir>` under the hood and prints the URL on stdout (also copied to clipboard).

### Subcommands

The agent invokes these via the skill. To run them yourself, point at whichever
location your agent installed the skill into (e.g.
`~/.claude/skills/cloudshare/` for Claude Code,
`~/.codex/skills/cloudshare/` for Codex, etc.):

```bash
# list all your past shares
bash <skill-dir>/resources/list.sh

# delete one (revokes URL, keeps others)
bash <skill-dir>/resources/delete.sh <slug>

# rotate the token for one share (old token → 401, new URL printed)
bash <skill-dir>/resources/rotate.sh <slug>
```

## Security model

- Each share gets its own `?token=<32 hex chars>` query parameter.
- The Pages Function middleware validates the token against an env var lookup table (`SHARE_TOKENS_JSON`) before serving any path under `/r/<slug>/`.
- Wrong/missing token → `401`.
- Unknown slug → `404`.
- `Referrer-Policy: no-referrer` and `X-Robots-Tag: noindex, nofollow` set via `_headers`.
- **Anyone with the URL has access.** Treat it like a password.

## Limits

Cloudflare Pages free tier:
- 500 deploys/month
- 25 MB per file
- 100 MB per deploy total (mirror is redeployed on every share)
- Unlimited bandwidth

## Reset

To reconfigure from scratch (new token, new domain), re-run setup:

```bash
curl -fsSL https://raw.githubusercontent.com/alanho/cloudshare-skills/main/setup.sh | bash
```

It will detect existing config and ask before overwriting.

## Uninstall

```bash
# Remove the skill from your agent
npx skills remove -a claude-code -s cloudshare

# Wipe local mirror and config
rm -rf ~/.config/cloudshare

# Delete the Cloudflare Pages project itself (optional)
npx wrangler pages project delete <your-project-name>
```

## Roadmap

See [ROADMAP.md](./ROADMAP.md).

## License

MIT — see [LICENSE](./LICENSE).
