#!/bin/zsh
# Builds Speakeasy.app, signs it with our Developer ID, and installs it to ~/Applications.
# Usage: ./build.sh            build + install + relaunch
#        ./build.sh --no-install
set -euo pipefail
cd "${0:A:h}"

APP=build/Speakeasy.app
IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
DEST="$HOME/Applications/Speakeasy.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target arm64-apple-macosx27.0 Sources/*.swift -o "$APP/Contents/MacOS/Speakeasy"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

[[ "${1:-}" == "--no-install" ]] && exit 0

pkill -x Speakeasy || true
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
open "$DEST"
echo "installed and launched $DEST"
