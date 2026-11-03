#!/usr/bin/env bash
# Pubblica site/ sul repo GitHub Pages R3tr003/carspot-site (dominio carspot-eu.com).
# Uso: scripts/publish-site.sh ["messaggio di commit"]
set -euo pipefail

REPO="R3tr003/carspot-site"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MSG="${1:-Aggiorna sito}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh repo clone "$REPO" "$WORK/site" -- --quiet
rsync -a --delete --exclude .git "$ROOT/site/" "$WORK/site/"
cd "$WORK/site"
git add -A
if git diff --cached --quiet; then
  echo "Niente da pubblicare."
  exit 0
fi
git commit -q -m "$MSG"
git push -q
echo "Pubblicato: https://carspot-eu.com (GitHub Pages aggiorna in 1-2 minuti)"
