# Coding Agent Usage Plugin

A native, privacy-first macOS menu bar app for local Codex usage analytics. Supports Apple Silicon and Intel Macs running macOS 13 or newer.

## One-command install

```bash
curl -fsSL https://raw.githubusercontent.com/CleverAutoman/coding-agent-usage-plugin/main/install.sh | zsh
```

The installer downloads the latest universal release, installs it to `~/Applications/Codex Usage.app`, and launches it. No Homebrew, Xcode, API key, or Swift toolchain is required.

It shows today's and this month's exact token totals in circular gauges, cached-input ratio, request and session counts, a 14-day gradient trend chart with explicit totals and daily values, frequency change, and the account's real usage-window percentage reported by OpenAI. It also estimates the remaining and total token equivalents for that quota window from locally observed token usage. It detects the local plan type and refreshes the official plan guidance from `https://learn.chatgpt.com/docs/pricing.md`.

OpenAI does not publish fixed daily, monthly, or weekly raw-token caps for ChatGPT plans. Official plan estimates are expressed as local messages per rolling five-hour window, and actual consumption varies with model, context, reasoning, tools, and caching. The quota token number is therefore marked as an estimate: observed raw tokens in the current window divided by the reported used percentage. The percentage is rounded and different token types can have different weights, so it is not a guaranteed allowance.

## Privacy

The app reads only token-count events from `~/.codex/sessions/**/*.jsonl`. It does not use an API key or inspect prompt/message content. It requests only OpenAI's public pricing documentation to refresh plan guidance.

## Build

Requires macOS 13 or newer and Swift 6.

```bash
swift test
scripts/build-app.sh
```

The app bundle is created at `dist/Codex Usage.app`.

For a machine-readable local snapshot, run `swift run codex-usage`.

To build a universal Apple Silicon + Intel bundle:

```bash
scripts/build-universal-app.sh
```

## Install from source

```bash
scripts/install-from-source.sh
```

This copies the bundle to `~/Applications/Codex Usage.app` and launches it. Use the toggle in the popover to enable launch at login.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/CleverAutoman/coding-agent-usage-plugin/main/uninstall.sh | zsh
```

## Releases

Pushing a tag such as `v0.5.0` runs tests on GitHub Actions, builds a universal signed app bundle, and publishes the ZIP plus its SHA-256 checksum as a GitHub Release.

## Notes

Codex's local session-event schema is not a public compatibility contract. The parser accepts the current `last_token_usage` shape and includes a cumulative-total fallback, but future Codex updates may require a small parser adjustment.
