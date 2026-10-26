#!/bin/zsh
# Build MenuTuck.app and package it as build/MenuTuck.dmg and build/MenuTuck-macOS.zip.
# Usage: scripts/package.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SKIP_INSTALL=1 ./scripts/build-app.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr build/MenuTuck.app "$STAGE/MenuTuck.app"
codesign --verify --deep --strict "$STAGE/MenuTuck.app"
ln -s /Applications "$STAGE/Applications"

rm -f build/MenuTuck.dmg build/MenuTuck-macOS.zip
ditto -c -k --norsrc --noextattr --keepParent build/MenuTuck.app build/MenuTuck-macOS.zip
hdiutil create -quiet -volname MenuTuck -srcfolder "$STAGE" -format UDZO build/MenuTuck.dmg

shasum -a 256 build/MenuTuck.dmg build/MenuTuck-macOS.zip
