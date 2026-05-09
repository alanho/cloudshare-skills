# cloudshare-skills

Agent skill that uploads a local file (HTML, image, PDF, directory) to Cloudflare Pages and returns a token-protected shareable URL.

One stable, friendly subdomain per user (e.g. `purple-tiger-42.pages.dev`). Every subsequent share = a new path under that domain with its own token.

```
https://purple-tiger-42.pages.dev/r/trip-options-9f3a/?token=4b7c8d2e1a9f
                                   └─ filename slug + 4-char suffix
                                   └─ per-path token, server-side lookup
```

## Install

Install into any agent supported by [vercel-labs/skills](https://github.com/vercel-labs/skills):

```bash
npx skills add alanho/cloudshare-skills
```

Or target a specific agent:

```bash
npx skills add alanho/cloudshare-skills -a claude-code
npx skills add alanho/cloudshare-skills -a codex
npx skills add alanho/cloudshare-skills -a opencode
```

## First-run setup (~3 min)

On the first share, the skill walks you through:

1. Creating a Cloudflare account (free) at https://dash.cloudflare.com/sign-up
2. Authenticating — either `npx wrangler login` (browser OAuth, recommended) or paste an API token from https://dash.cloudflare.com/profile/api-tokens with permissions:
   - `Account: Cloudflare Pages: Edit`
   - `Account: Account Settings: Read`
3. Picking your personal `cloudshare` subdomain. The wizard suggests something like `purple-tiger-42`; accept with Enter or type your own.

Credentials and project name are saved to `~/.config/cloudshare/config.env` (chmod 600).

## Usage

Trigger by asking the agent:

- "share this file"
- "publish this html"
- "make a shareable link"
- "upload to cloudflare"
- `/cloudshare`

The skill calls `bash ./resources/deploy.sh <path-to-file-or-dir>` under the hood and prints the URL on stdout (also copied to clipboard).

### Subcommands

```bash
# list all your past shares
bash ~/.claude/skills/cloudshare/resources/list.sh

# delete one (revokes URL, keeps others)
bash ~/.claude/skills/cloudshare/resources/delete.sh <slug>

# rotate the token for one share (old token → 401, new URL printed)
bash ~/.claude/skills/cloudshare/resources/rotate.sh <slug>
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

## Uninstall

```bash
npx skills remove -a claude-code -s cloudshare
```

To also wipe your local mirror and config:
```bash
rm -rf ~/.config/cloudshare
```

To delete the Cloudflare Pages project itself, log into the dashboard or run:
```bash
npx wrangler pages project delete <your-project-name>
```

## Roadmap

See [ROADMAP.md](./ROADMAP.md).

## License

MIT — see [LICENSE](./LICENSE).
