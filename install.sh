#!/bin/bash
# Install Hertz from the latest GitHub release into ~/Applications and launch
# it. No clone, no toolchain, no admin password.
#
#   curl -fsSL https://raw.githubusercontent.com/pranshugupta54/hertz/main/install.sh | bash
set -euo pipefail

REPO="pranshugupta54/hertz"
DEST="$HOME/Applications/Hertz.app"

if [ -t 1 ]; then
    G=$'\033[0;32m'; B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0;31m'; N=$'\033[0m'
else
    G=''; B=''; D=''; R=''; N=''
fi

step() { printf "  ${G}✓${N}  %-16s${D}%s${N}\n" "$1" "${2:-}"; }
fail() { printf "  ${R}✗  %s${N}\n\n" "$1"; exit 1; }

printf '\n'
printf "  ${G}${B}∿ HERTZ${N}\n"
printf "  ${D}native macOS system monitor${N}\n\n"

JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" || true)
VERSION=$(printf '%s' "$JSON" | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
URL=$(printf '%s' "$JSON" | grep '"browser_download_url"' | grep '\.zip"' | head -1 \
    | sed -E 's/.*"(https[^"]+)".*/\1/')
[ -n "$URL" ] || fail "No release found. Try again in a moment."
step "release" "$VERSION"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/Hertz.app.zip" || fail "Download failed."
ditto -x -k "$TMP/Hertz.app.zip" "$TMP"
step "downloaded"

osascript -e 'quit app "Hertz"' 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
mv "$TMP/Hertz.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
step "installed" "~/Applications/Hertz.app"

open "$DEST"
printf "\n  ${B}Hertz ${VERSION#v} is live in your menu bar.${N}\n"
printf "  ${D}It self-updates from GitHub — nothing else to do.${N}\n\n"
