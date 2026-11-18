#!/bin/bash
# Pitwall installer.
#
#   curl -fsSL https://aidarkazybekov.github.io/pitwall/install.sh | bash
#
# Downloads the latest release from GitHub, checks its SHA-256, installs Pitwall.app into
# /Applications (or ~/Applications when /Applications isn't writable) and opens it.
# Run it again to update. Read it first: https://github.com/aidarkazybekov/pitwall/blob/main/docs/install.sh
#
# Options (environment variables):
#   PITWALL_INSTALL_DIR=<dir>   install there instead (no quitting of a running copy)
#   PITWALL_NO_OPEN=1           don't open the app afterwards
set -euo pipefail

REPO="aidarkazybekov/pitwall"
ASSET="Pitwall-macOS-arm64.zip"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Pitwall is a Mac app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "Pitwall needs macOS 15 or later; this Mac has $(sw_vers -productVersion)."
[ "$(uname -m)" = "arm64" ] || fail "The prebuilt app is for Apple Silicon. On Intel Macs, build from source: https://github.com/$REPO#build-from-source"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold "Downloading Pitwall…"
curl -fsSL --retry 2 "$URL" -o "$tmp/$ASSET" || fail "Download failed: $URL"

if curl -fsSL "$URL.sha256" -o "$tmp/$ASSET.sha256" 2>/dev/null; then
  expected=$(awk '{print $1}' "$tmp/$ASSET.sha256")
  actual=$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')
  [ "$expected" = "$actual" ] || fail "Checksum mismatch, so the download may be damaged. Nothing was installed."
  echo "Checksum verified."
else
  echo "No checksum published for this release; skipping verification."
fi

ditto -x -k "$tmp/$ASSET" "$tmp/unpacked"
[ -d "$tmp/unpacked/Pitwall.app" ] || fail "The download didn't contain Pitwall.app."

# Where to install: an explicit dir, else wherever it's already installed, else /Applications if writable.
if [ -n "${PITWALL_INSTALL_DIR:-}" ]; then
  dest="$PITWALL_INSTALL_DIR"
else
  dest=""
  for d in "/Applications" "$HOME/Applications"; do
    if [ -d "$d/Pitwall.app" ] || [ -d "$d/ClaudeBoard.app" ]; then dest="$d"; break; fi
  done
  if [ -z "$dest" ]; then
    if [ -w "/Applications" ]; then dest="/Applications"; else dest="$HOME/Applications"; fi
  fi
  # ClaudeBoard is Pitwall's old name: quit it too, so both never run at once.
  for app in Pitwall ClaudeBoard; do
    if pgrep -x "$app" >/dev/null 2>&1; then
      echo "Quitting the running $app…"
      osascript -e "quit app \"$app\"" >/dev/null 2>&1 || pkill -x "$app" || true
      sleep 1
    fi
  done
fi
mkdir -p "$dest"

rm -rf "$dest/Pitwall.app"
ditto "$tmp/unpacked/Pitwall.app" "$dest/Pitwall.app"
xattr -dr com.apple.quarantine "$dest/Pitwall.app" 2>/dev/null || true

# Upgrading from ClaudeBoard: Pitwall copies its settings and tasks on first launch, so the old app can go.
if [ -d "$dest/ClaudeBoard.app" ]; then
  rm -rf "$dest/ClaudeBoard.app"
  echo "Replaced ClaudeBoard.app: Pitwall is its new name, and your settings and tasks come along."
fi

version=$(defaults read "$dest/Pitwall.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
bold "Pitwall ${version:+$version }is installed in $dest."

if [ -z "${PITWALL_NO_OPEN:-}" ]; then
  open "$dest/Pitwall.app"
  echo "Opening it now. Run this command again any time to update."
fi
