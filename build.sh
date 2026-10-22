#!/bin/zsh
# Builds Speakeasy.app, signs it with our Developer ID, and installs it to ~/Applications.
# Usage: ./build.sh            build + install + relaunch
#        ./build.sh --no-install
set -euo pipefail
cd "${0:A:h}"

APP=build/Speakeasy.app
# Signing identity: $SPEAKEASY_SIGN_IDENTITY if set, else the first line of the untracked
# .signing-identity file, else ad-hoc ("-"). Ad-hoc builds work, but macOS forgets the
# Accessibility grant after each rebuild.
IDENTITY="${SPEAKEASY_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f .signing-identity ]]; then
    IDENTITY="$(head -n 1 .signing-identity)"
fi
IDENTITY="${IDENTITY:--}"
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "note: signing identity not found, signing ad-hoc"
    IDENTITY="-"
fi
DEST="$HOME/Applications/Speakeasy.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
xcrun actool Speakeasy.icon --compile "$APP/Contents/Resources" --app-icon Speakeasy \
    --platform macosx --target-device mac --minimum-deployment-target 27.0 \
    --include-all-app-icons --output-partial-info-plist build/icon-partial.plist >/dev/null
swiftc -O -target arm64-apple-macosx27.0 Sources/*.swift -o "$APP/Contents/MacOS/Speakeasy"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "built $APP"

[[ "${1:-}" == "--no-install" ]] && exit 0

pkill -x Speakeasy || true
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
open "$DEST"
echo "installed and launched $DEST"
