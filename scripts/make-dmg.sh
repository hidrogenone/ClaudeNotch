#!/bin/bash
# Builds a polished drag-to-Applications DMG from build/ClaudeNotch.app.
# Requires: brew install create-dmg. Background image lives in Resources/.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGING="build/dmg-staging"
rm -rf "$STAGING" build/ClaudeNotch.dmg
mkdir -p "$STAGING"
cp -R build/ClaudeNotch.app "$STAGING/"

PATH="/opt/homebrew/bin:$PATH" create-dmg \
  --volname "ClaudeNotch" \
  --volicon "Resources/AppIcon.icns" \
  --background "Resources/dmg-background.png" \
  --window-pos 200 150 \
  --window-size 660 460 \
  --icon-size 128 \
  --icon "ClaudeNotch.app" 165 200 \
  --hide-extension "ClaudeNotch.app" \
  --app-drop-link 495 200 \
  "build/ClaudeNotch.dmg" \
  "$STAGING"

rm -rf "$STAGING"
echo "Built build/ClaudeNotch.dmg"
