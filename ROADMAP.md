# Roadmap

Tracking ideas and parked work for cloudshare. Items here are not committed deliverables — open an issue or PR if you want to drive one of them.

## v1 (shipped)

- One Cloudflare Pages project per user, chosen at first-run setup
- Per-share random path with friendly slug derived from filename + 4-char hex suffix
- Per-path token stored in project env var `SHARE_TOKENS_JSON`
- Page middleware validates `?token=` per `/r/<slug>/` path
- File types supported: HTML, images (PNG/JPG/GIF/WebP), PDF, directories
- Subcommands: `list`, `delete`, `rotate`
- Local mirror at `~/.config/cloudshare/projects/<name>/` redeployed on each share
- Multi-agent install via `npx skills add` (Claude Code, Codex, OpenCode, +50 more)

## v2+ (parked)

### Custom domain support
Cloudflare Pages free tier supports custom domains via DNS CNAME. Add a `cloudshare domain add <yourdomain.com>` subcommand that:
1. Verifies DNS points to `<project>.pages.dev`
2. Calls Cloudflare API to attach the custom domain
3. Updates output URLs to use the custom domain

### TTL / auto-expiry per share
Each share could carry an expiry timestamp. Implementation options:
- Store `{slug: {token, expiresAt}}` in `SHARE_TOKENS_JSON` and have middleware reject expired entries.
- A Worker cron + KV that removes expired slugs from the env var.
- Simpler: a local `cron` job that runs `cloudshare cleanup` to delete expired shares.

### Cookie auth (referrer hardening)
Currently the token sits in the URL — leaks via referrer headers are mitigated by `Referrer-Policy: no-referrer`, but not fully eliminated. Improvement:
1. First request with valid `?token=` sets an HTTP-only cookie.
2. Middleware redirects to the clean URL (no token).
3. Subsequent requests authenticate via cookie.

### Codex / OpenCode adapter testing
v1 trusts that `vercel-labs/skills` correctly installs into non-Claude agents. Verify hands-on:
- Codex: invoke trigger phrases in a real `codex` session, ensure the skill is found and scripts run.
- OpenCode: same.
- Document any agent-specific quirks in `docs/agents.md`.

### Web UI / dashboard for managing shares
A small static app served from the same project root that lists shares, lets the owner copy URLs, rotate tokens, and delete shares — gated behind an "owner token" stored locally only.

### Mirror cleanup / size management
The local mirror grows unbounded; eventually hits the 100 MB Pages deploy cap. Options:
- `cloudshare prune --before=<date>` to delete old shares.
- Auto-prune oldest when nearing cap, with confirmation prompt.
- Compress static assets before deploy.

### Per-share expiry view counter
Optionally limit a share to N views by tracking hits in a Cloudflare KV namespace.

### Encrypt at rest
Encrypt mirror contents locally so loss of the laptop doesn't expose past shares.

### Multi-account support
Today the skill assumes one Cloudflare account per user. Add `cloudshare profile use <name>` to switch between work / personal accounts.

### Automated cleanup of unused npm cache
`npx wrangler@latest` re-downloads each session by default. Cache it under `~/.config/cloudshare/wrangler-cache/` to speed up first deploy after install.

### Bring-your-own-Worker storage
Replace `SHARE_TOKENS_JSON` env var with a Cloudflare KV namespace bound to the Pages project. Removes the upper bound on tokens-per-project (env vars cap around 5 KB).

### `cloudshare share <url>` to forward content
Take a URL, fetch it, save as static, share it (proxy mode).
