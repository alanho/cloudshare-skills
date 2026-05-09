#!/usr/bin/env bash
# slug.sh — generate slugs for cloudshare projects and share paths.
#
# Usage:
#   slug.sh project          → adjective-noun-NN (e.g. purple-tiger-42)
#                              suitable for Cloudflare Pages project name
#   slug.sh path <filename>  → <basename>-<rand4> (e.g. trip-options-9f3a)
#                              suitable for /r/<slug>/ path under the project

set -euo pipefail

mode="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
words_file="${script_dir}/words.txt"

case "$mode" in
  project)
    if [ ! -f "$words_file" ]; then
      echo "ERROR: words.txt not found at $words_file" >&2
      exit 1
    fi
    # words.txt: adjectives, then `---`, then nouns
    adjectives=$(awk '/^---$/{exit} {print}' "$words_file")
    nouns=$(awk 'p{print} /^---$/{p=1}' "$words_file")

    adj=$(printf '%s\n' "$adjectives" | awk 'NF' | shuf -n 1 2>/dev/null || \
          printf '%s\n' "$adjectives" | awk 'NF' | sort -R | head -n 1)
    noun=$(printf '%s\n' "$nouns" | awk 'NF' | shuf -n 1 2>/dev/null || \
          printf '%s\n' "$nouns" | awk 'NF' | sort -R | head -n 1)
    num=$(( RANDOM % 100 ))
    printf '%s-%s-%02d\n' "$adj" "$noun" "$num"
    ;;

  path)
    input="${2:-}"
    if [ -z "$input" ]; then
      echo "ERROR: slug.sh path <filename>" >&2
      exit 1
    fi
    base=$(basename -- "$input")
    # strip extension
    base="${base%.*}"
    # lowercase, replace non-alphanumeric with -, collapse repeats, trim
    base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
                                 | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g; s/-+/-/g')
    # cap base length
    base="${base:0:40}"
    base="${base%-}"
    [ -z "$base" ] && base="share"
    rand4=$(openssl rand -hex 2)
    printf '%s-%s\n' "$base" "$rand4"
    ;;

  *)
    cat <<'EOF' >&2
Usage:
  slug.sh project          → adjective-noun-NN
  slug.sh path <filename>  → <basename>-<rand4>
EOF
    exit 1
    ;;
esac
