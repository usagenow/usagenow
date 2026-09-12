# UsageNow 0.2.0

AI coding usage tracker for macOS. Monitor usage, limits, reset times, and token activity across Codex and Claude Code, from the menu bar.

## What's in this release

- **Real provider data.** Codex limits, reset times, and plan come from the official `codex app-server`, falling back to the latest limits recorded in local sessions when it isn't reachable. Token, request, and model activity for both tools comes from local session files.
- **Desktop widget.** Small and medium widgets. Small shows each provider's tightest window and the next reset; medium gives each provider a column of windows. The widget renders a sanitized snapshot the app publishes — it never touches providers, files, the keychain, or the network.
- **Providers settings.** Track Codex and Claude Code independently. A provider that's off is never refreshed or read from disk.
- **Claude usage limits** (experimental, off by default). Uses your existing Claude Code sign-in. UsageNow never modifies or stores those credentials; when the saved sign-in has expired it asks the Claude Code CLI to renew its own.
- **Appearance** — Light, Dark, or System — and menu bar display modes.
- **Limits don't vanish.** When a provider can't be reached, the last known limits stay for a day, marked stale, instead of leaving an empty panel.
- Usage reads as what's **left** ("58% left"), and a limit window that a provider doesn't report is never invented.

## Privacy

Everything stays on your Mac. Optional anonymous analytics are off by default and carry only the app version, macOS version, architecture, and a random installation ID — never usage values, prompts, file paths, project names, or credentials.

## Install

Download `UsageNow-0.2.0.dmg` and drag UsageNow to Applications, or `brew install --cask usagenow`.

Requires macOS 15 or later. Signed with a Developer ID and notarized by Apple.

**SHA-256:** `15b7ce8c26770e9d401df494aa842691b7fb242f04a0849cd3802465a734d4bc`
