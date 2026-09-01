#!/bin/zsh
set -euo pipefail

plugin_root=${0:A:h:h}
cd "$plugin_root"

"$plugin_root/scripts/build-universal-app.sh"
archive="$plugin_root/dist/Codex-Usage-macOS-universal.zip"
checksum="$archive.sha256"

rm -f "$archive" "$checksum"
ditto -c -k --sequesterRsrc --keepParent "$plugin_root/dist/Codex Usage.app" "$archive"
cd "$plugin_root/dist"
shasum -a 256 "${archive:t}" > "${checksum:t}"

echo "$archive"
echo "$checksum"
