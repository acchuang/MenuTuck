#!/bin/zsh
# Build MenuTuck.app and package it as build/MenuTuck.dmg and build/MenuTuck-macOS.zip.
# Usage: scripts/package.sh
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/MenuTuck.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f build/MenuTuck.dmg build/MenuTuck-macOS.zip
ditto -c -k --keepParent build/MenuTuck.app build/MenuTuck-macOS.zip
hdiutil create -quiet -volname MenuTuck -srcfolder "$STAGE" -format UDZO build/MenuTuck.dmg

shasum -a 256 build/MenuTuck.dmg build/MenuTuck-macOS.zip
