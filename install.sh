#!/bin/zsh
set -euo pipefail

repo="CleverAutoman/coding-agent-usage-plugin"
asset="Codex-Usage-macOS-universal.zip"
download_url="https://github.com/$repo/releases/latest/download/$asset"
install_root="$HOME/Applications"
target_app="$install_root/Codex Usage.app"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-install.XXXXXX")
trap 'rm -rf "$temp_root"' EXIT

echo "Downloading the latest Codex Usage release..."
curl --fail --location --progress-bar "$download_url" --output "$temp_root/$asset"
ditto -x -k "$temp_root/$asset" "$temp_root/unpacked"

source_app="$temp_root/unpacked/Codex Usage.app"
if [[ ! -d "$source_app" ]]; then
  echo "Install failed: the release archive does not contain Codex Usage.app" >&2
  exit 1
fi

osascript -e 'tell application id "local.codex.usage-menubar" to quit' >/dev/null 2>&1 || true
mkdir -p "$install_root"
rm -rf "$target_app"
ditto "$source_app" "$target_app"
xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
open "$target_app"

echo "Installed Codex Usage to: $target_app"
