#!/bin/zsh
set -euo pipefail

plugin_root=${0:A:h:h}
"$plugin_root/scripts/build-app.sh"
install_root="$HOME/Applications"
source_app="$plugin_root/dist/Codex Usage.app"
target_app="$install_root/Codex Usage.app"
mkdir -p "$install_root"
ditto "$source_app" "$target_app"
open "$target_app"
echo "Installed: $target_app"
