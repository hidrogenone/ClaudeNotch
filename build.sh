#!/bin/bash
# Builds ClaudeNotch.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

# Universal so the app runs on both Apple Silicon and Intel Macs.
swift build -c release --arch arm64 --arch x86_64

APP="build/ClaudeNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/ClaudeNotch "$APP/Contents/MacOS/ClaudeNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Gatekeeper lets it run locally.
codesign --force --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeNotch"))"
