#!/bin/zsh
set -euo pipefail

plugin_root=${0:A:h:h}
cd "$plugin_root"
swift build -c release
bin_path=$(swift build -c release --show-bin-path)
app_path="$plugin_root/dist/Codex Usage.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/CodexUsageMenubar" "$app_path/Contents/MacOS/CodexUsageMenubar"
cp "$plugin_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
echo "$app_path"
