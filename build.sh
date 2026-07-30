#!/bin/bash
# Builds ClaudeNotch.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/ClaudeNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeNotch "$APP/Contents/MacOS/ClaudeNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Gatekeeper lets it run locally.
codesign --force --sign - "$APP"

echo "Built $APP"
