---
name: codex-usage-menubar
description: Build, install, or diagnose the local Codex Usage macOS menu bar monitor in this plugin. Use when the user asks to install the monitor, verify its local token analytics, troubleshoot missing usage, or explain its metrics.
---

# Codex Usage Menubar

Operate the companion native macOS app without exposing conversation content.

## Build and verify

From the plugin root:

1. Run `swift test`.
2. Run `scripts/build-app.sh`.
3. Confirm that `dist/Codex Usage.app` exists and is ad-hoc signed.

Use `swift run codex-usage` when a numeric, machine-readable snapshot is needed without launching the GUI.

## Install

Run `scripts/install.sh` only after the user asks to install or launch the app. It copies the app to `~/Applications/Codex Usage.app` and opens it.

## Data and privacy

- Read token counters only from `~/.codex/sessions/**/*.jsonl`.
- Use `event_msg` records whose `payload.type` is `token_count`.
- Aggregate `payload.info.last_token_usage` by the event timestamp.
- Never display, transmit, summarize, or log user prompts, assistant messages, tool arguments, or tool outputs.
- Treat the on-disk Codex event schema as an implementation detail that may change. If usage becomes zero unexpectedly, inspect only event type names and token-count object keys before changing the parser.

## Metric definitions

- Today/month totals: sum `last_token_usage.total_tokens` within the local calendar period.
- Requests: count token-count events.
- Sessions: count distinct rollout files with token activity that day.
- Frequency change: today's request count versus the average of active days among the previous seven days.
- Cached ratio: cached input tokens divided by input tokens.
- Usage window: the newest local `rate_limits.primary` snapshot; it is not a billing total.
