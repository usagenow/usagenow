# UsageNow 0.3.0

AI coding usage tracker for macOS. Usage, limits, reset times, and token activity across Codex, Claude Code, Gemini CLI, and Antigravity, from the menu bar.

## New

- **Gemini CLI** — tokens, requests, and models from its local sessions. It reports no usage limits, so none are shown.
- **Antigravity** — usage limits from the Antigravity app while it runs, read over loopback with no credentials.
- **Activity by model** — a “Models today” list for Claude Code, Codex, and Gemini CLI, most active first. Account limits are never split by model.
- **Team plans** — Claude shows the seat (e.g. Team · Premium); Codex shows Team, Business, and Enterprise.
- **Reorder providers** — drag them in Settings; the popover and widget follow.
- GitHub Copilot and Cursor are listed as coming soon.

## Fixed

- Claude usage limits no longer prompt for your login password, and come back on their own after you run Claude Code.
- A Claude limit window that reset while you were away stays visible instead of disappearing, and limits you hit show up without any sign-in.
- The last known limits survive quitting or updating the app.

## Install

Download `UsageNow-0.3.0.dmg` below and drag UsageNow to Applications.

Requires macOS 15 or later. Signed with a Developer ID and notarized by Apple.

**SHA-256:** `d036b78583a6e6aa52b5a1e726b5afcf720cd8537511c7375b0e62fc23e63bc3`
