#!/bin/zsh
# Build MenuTuck.app from the Swift package and install to /Applications/MenuTuck.app.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
# Env:   SIGN_IDENTITY  codesign identity. Default: ad-hoc ("-").
#        SKIP_INSTALL   set to 1 to leave /Applications/MenuTuck.app untouched.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/MenuTuck.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MenuTuck"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MenuTuck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" --identifier com.acchuang.MenuTuck --timestamp=none "$APP"

# Install to /Applications/MenuTuck.app so macOS 27's sandboxed MenuBarAgent
# always resolves CFBundleIdentifier ("com.acchuang.MenuTuck") and keeps MenuTuck's
# own status items and dividers visible when MBAssessmentModeAssertion is active.
if [ "${SKIP_INSTALL:-0}" != 1 ] && [ -w "/Applications" ]; then
    rm -rf "/Applications/MenuTuck.app"
    cp -R "$APP" "/Applications/MenuTuck.app"
    echo "Built $APP and installed to /Applications/MenuTuck.app (signed with: $SIGN_IDENTITY)"
else
    echo "Built $APP (signed with: $SIGN_IDENTITY)"
fi
