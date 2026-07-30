#!/bin/bash
# ClaudeNotch installer — downloads the latest release, installs it to
# /Applications and clears the quarantine flag so Gatekeeper doesn't block
# the (ad-hoc signed) app. Run it yourself, read it first — it's short.
#
#   curl -fsSL https://raw.githubusercontent.com/hidrogenone/ClaudeNotch/main/install.sh | bash
set -euo pipefail

ZIP_URL="https://github.com/hidrogenone/ClaudeNotch/releases/latest/download/ClaudeNotch.zip"
TMP="$(mktemp -d /tmp/claudenotch.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Downloading latest ClaudeNotch…"
curl -fsSL -o "$TMP/ClaudeNotch.zip" "$ZIP_URL"

echo "▸ Unpacking…"
ditto -x -k "$TMP/ClaudeNotch.zip" "$TMP/unpacked"

echo "▸ Installing to /Applications…"
osascript -e 'tell application "ClaudeNotch" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/ClaudeNotch.app
mv "$TMP/unpacked/ClaudeNotch.app" /Applications/

echo "▸ Clearing quarantine flag…"
xattr -dr com.apple.quarantine /Applications/ClaudeNotch.app 2>/dev/null || true

echo "▸ Launching…"
open /Applications/ClaudeNotch.app

echo "✓ Done — hover your notch."
