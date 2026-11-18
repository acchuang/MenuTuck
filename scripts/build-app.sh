#!/bin/zsh
# Build MenuTuck.app from the Swift package and install to /Applications/MenuTuck.app.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
# Env:   SIGN_IDENTITY  codesign identity. Default: "MenuTuck Dev" if in the keychain, else ad-hoc ("-").
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

# MenuBarAgent resolves no bundle ID for an ad-hoc signed app, so while hiding is on
# the assertion allowlist misses MenuTuck and its own toggle and dividers draw blank.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    # Capture first: under pipefail, grep -q exiting early can SIGPIPE `security` and fail the test.
    IDENTITIES="$(security find-identity -v -p codesigning || true)"
    if grep -q '"MenuTuck Dev"' <<<"$IDENTITIES"; then
        SIGN_IDENTITY="MenuTuck Dev"
    else
        SIGN_IDENTITY="-"
        echo "warning: ad-hoc signing; MenuTuck's own menu bar items will be blank while icons are hidden" >&2
    fi
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier com.acchuang.MenuTuck --timestamp=none "$APP"

if [ "${SKIP_INSTALL:-0}" != 1 ] && [ -w "/Applications" ]; then
    rm -rf "/Applications/MenuTuck.app"
    cp -R "$APP" "/Applications/MenuTuck.app"
    echo "Built $APP and installed to /Applications/MenuTuck.app (signed with: $SIGN_IDENTITY)"
else
    echo "Built $APP (signed with: $SIGN_IDENTITY)"
fi
