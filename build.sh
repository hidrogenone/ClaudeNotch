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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Developer ID + hardened runtime when the certificate is present (required
# for notarization); ad-hoc fallback so contributors can still build.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (no Developer ID certificate found)"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeNotch"))"
