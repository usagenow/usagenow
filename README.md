# UsageNow

**See what’s left. Keep building.**

A native macOS menu bar app for tracking Codex and Claude Code usage, limits, reset times, and token activity.

Website: [usagenow.com](https://usagenow.com)

## Current status

Early development. UsageNow reads real Codex and Claude Code data from your Mac. Which data is available depends on the tool:

| | Codex | Claude Code |
|---|---|---|
| Usage limits and reset times | ✓ from the official `codex app-server` | Experimental, opt-in (see below) |
| Plan | ✓ | ✓ from Claude Code’s cached account profile |
| Tokens and requests today | ✓ from local session files | ✓ from local session files |
| Most recent model | ✓ | ✓ |

Limit windows are whatever the provider reports. An account may have only a weekly limit, for example, and UsageNow never invents a missing window or shows a fake 0%.

Token and request counts are **local activity** observed in session files on this Mac. They include cached input and don’t necessarily match billing or quota consumption.

## Highlights

- **macOS native.** SwiftUI and `MenuBarExtra`. Lives in the menu bar, not the Dock.
- **Codex + Claude Code** side by side: usage limits, reset times, and daily token and request activity.
- **Pick your providers.** Turn Codex and Claude Code on or off in Settings › Providers. A provider that’s off is never refreshed and never read from disk.
- **Local-first.** Your usage data stays on your Mac.
- **Open source** under the MIT License.
- **No accounts required.**

## Requirements

- macOS 15 or later
- Xcode 26 or later to build

## Building

Clone the repository, open `UsageNow.xcodeproj`, and run the **UsageNow** scheme. The UsageNow symbol appears in the menu bar; click it to open the popover.

From the command line:

```sh
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow build
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow test
```

### Data sources

- **Codex:** limits and plan come from the official Codex CLI’s app-server (`codex app-server`, `account/rateLimits/read`), which UsageNow runs locally. The app-server authenticates itself, so UsageNow never reads Codex credentials. If it’s unavailable, UsageNow falls back to the latest limits recorded in `~/.codex/sessions` and marks them as stale.
- **Claude Code:** activity comes from `~/.claude/projects`, and the plan from `~/.claude.json`. Only timestamps, identifiers, model names, and token counts are extracted. Prompts, responses, and code are never stored, logged, or sent anywhere.
- **Claude usage limits (experimental, off by default):** Claude Code doesn’t store its limits locally. When you turn on **Settings › General › Fetch Claude usage limits**, UsageNow reads your Claude Code sign-in from the keychain (macOS asks for permission) and queries Anthropic’s undocumented usage endpoint directly. The token stays in memory and is only sent to Anthropic. This may stop working without notice.

UsageNow honors `CODEX_HOME` and `CLAUDE_CONFIG_DIR` when they’re set.

### Roadmap providers

Gemini CLI, Grok, DeepSeek, GLM, Qwen, Kimi, and Meta AI are listed in Settings › Providers as **Coming soon**. They’re labels only: no integration, no credentials, and no network or file access.

### Trying different states

Real providers run by default. For development, mock providers accept a scenario at launch: `normal`, `high`, `critical`, `unavailable`, `notInstalled`, `notAuthenticated`, `failing`, or `loading`.

```sh
open UsageNow.app --args -UsageNowMockCodex critical -UsageNowMockClaude failing
```

The shared scheme includes these as disabled launch arguments, which you can enable under **Product › Scheme › Edit Scheme › Run › Arguments**. SwiftUI previews cover the same states without running the app.

## Architecture

```
UsageNow/
  App/          Entry point and composition root (AppState)
  Domain/       Normalized models: ProviderSnapshot, UsageWindow, UsagePercentage, UsageLevel…
  Providers/    UsageProvider protocol; Codex, Claude Code, and mock providers
  Services/     UsageStore, auto-refresh, launch at login, keychain storage
  Preferences/  User preferences, provider selection, and option types
  Telemetry/    Telemetry events, network client, installation identity, consent
  Features/     MenuBar popover and Settings UI
  Components/   Shared views
  Utilities/    Formatters and app info
```

- **`ProviderCatalog`** is the single source of provider metadata — identifier, display name, artwork, and whether it’s available or on the roadmap.
- **Providers** turn tool-specific data into a normalized `ProviderSnapshot` with any number of usage windows and optional plan, model, and activity. Views depend only on this normalized state and hide data a provider doesn’t have.
- **`UsageStore`** refreshes all providers concurrently. It keeps the last good data when a refresh fails and exposes loading, empty, and per-provider error states.
- **Telemetry** is opt-in and off by default. Clients only receive a small set of events (install, daily active, updated, Codex or Claude Code detected) with the app version, macOS version, and a random installation ID. They never have access to provider data. No analytics server is configured yet, so nothing is sent.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

UsageNow source code is licensed under the MIT License. The UsageNow name, logo, icon, and other brand assets are not covered by the MIT License.

See [LICENSE](LICENSE).
