#!/bin/zsh
# Build MenuTuck.app and package it as build/MenuTuck.dmg and build/MenuTuck-macOS.zip.
# Usage: scripts/package.sh   (needs the "MenuTuck Release" signing cert in the keychain)
set -euo pipefail

cd "$(dirname "$0")/.."

# Sign with the self-signed "MenuTuck Release" cert (SHA-1 of the cert, not a secret). Its designated
# requirement is stable across versions, so users keep their Accessibility grant on update.
export SIGN_IDENTITY="${SIGN_IDENTITY:-BEAA9D39B2AF571B71D687B8F214FECE833AD432}"
SKIP_INSTALL=1 ./scripts/build-app.sh release

if ! codesign -d -r- build/MenuTuck.app 2>&1 | grep -q "certificate leaf"; then
    echo "error: build is ad-hoc signed (requirement is a cdhash); releases must use the MenuTuck Release cert" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr build/MenuTuck.app "$STAGE/MenuTuck.app"
codesign --verify --deep --strict "$STAGE/MenuTuck.app"
ln -s /Applications "$STAGE/Applications"

rm -f build/MenuTuck.dmg build/MenuTuck-macOS.zip
ditto -c -k --norsrc --noextattr --keepParent build/MenuTuck.app build/MenuTuck-macOS.zip
hdiutil create -quiet -volname MenuTuck -srcfolder "$STAGE" -format UDZO build/MenuTuck.dmg

shasum -a 256 build/MenuTuck.dmg build/MenuTuck-macOS.zip
