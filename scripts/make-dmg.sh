#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${ALTER_VERSION:-0.1.0}"
arch="${ALTER_ARCH:-$(uname -m)}"
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || exit 1
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$ ]] || exit 1
app="dist/$arch/Alter.app"
[[ -d "$app" ]] || { echo 'Run build.sh first'; exit 1; }
stage=$(mktemp -d "${TMPDIR:-/tmp}/alter-dmg.XXXXXX")
cp -RX "$app" "$stage/Alter.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$stage/THIRD_PARTY_NOTICES.txt"
cp docs/INSTALL.md "$stage/READ-ME-FIRST.txt"
output="dist/Alter-${version}-${arch}.dmg"
[[ ! -e "$output" ]] || { echo 'DMG already exists; refusing overwrite'; exit 1; }
hdiutil create -volname Alter -srcfolder "$stage" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "Alter-${version}-${arch}.dmg") > "$output.sha256"
echo "Packaged $output"
