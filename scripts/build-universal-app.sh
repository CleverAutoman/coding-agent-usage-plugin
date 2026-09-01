#!/bin/zsh
set -euo pipefail

plugin_root=${0:A:h:h}
cd "$plugin_root"

arm_triple="arm64-apple-macosx13.0"
intel_triple="x86_64-apple-macosx13.0"

swift build -c release --triple "$arm_triple"
swift build -c release --triple "$intel_triple"

arm_bin=$(swift build -c release --triple "$arm_triple" --show-bin-path)
intel_bin=$(swift build -c release --triple "$intel_triple" --show-bin-path)
app_path="$plugin_root/dist/Codex Usage.app"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
lipo -create \
  "$arm_bin/CodexUsageMenubar" \
  "$intel_bin/CodexUsageMenubar" \
  -output "$app_path/Contents/MacOS/CodexUsageMenubar"
cp "$plugin_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"

lipo -info "$app_path/Contents/MacOS/CodexUsageMenubar"
echo "$app_path"
