#!/bin/zsh
set -euo pipefail

target_app="$HOME/Applications/Codex Usage.app"
osascript -e 'tell application id "local.codex.usage-menubar" to quit' >/dev/null 2>&1 || true

if [[ -d "$target_app" ]]; then
  rm -rf "$target_app"
  echo "Removed: $target_app"
else
  echo "Codex Usage is not installed at: $target_app"
fi
