![UsageNow](docs/banner.png)

# UsageNow

**AI coding usage tracker for macOS.** Monitor usage, limits, reset times, and token activity across Codex, Claude Code, and Gemini CLI, from the menu bar.

*See what's left. Keep building.*

[usagenow.com](https://usagenow.com) · [Documentation](https://docs.usagenow.com) · [Download](https://github.com/usagenow/usagenow/releases/latest)

## Install

Download **UsageNow-0.2.0.dmg** from [usagenow.com](https://usagenow.com) or the [releases page](https://github.com/usagenow/usagenow/releases), then drag UsageNow to Applications.

A Homebrew cask (`brew install --cask usagenow`) is being submitted and will be listed here once it's accepted.

Requires macOS 15 or later. The app is signed with a Developer ID and notarized by Apple.

## What it reads

UsageNow reads real Codex, Claude Code, and Gemini CLI data from your Mac. Which data is available depends on the tool:

| | Codex | Claude Code | Gemini CLI |
|---|---|---|---|
| Usage limits and reset times | ✓ from the official `codex app-server` | ✓ experimental, opt-in (see below), plus limits Claude Code reports hitting | — not exposed locally |
| Plan | ✓, including Team, Business, and Enterprise | ✓ including a Team seat | — |
| Tokens and requests today | ✓ from local session files | ✓ from local session files | ✓ from local session recordings |
| Activity by model | ✓ | ✓ | ✓ |

Limit windows are whatever the provider reports. An account may have only a weekly limit, for example, and UsageNow never invents a missing window or shows a fake 0%.

**Account limits aren’t model limits.** A 5-hour or weekly window belongs to your account. The **Models today** list shows how today’s activity split across models — tokens and requests — and never a percentage, because no provider reports limits per model.

Token and request counts are **local activity** observed in session files on this Mac. They include cached input and don’t necessarily match billing or quota consumption.

## Highlights

- **macOS native.** SwiftUI and `MenuBarExtra`. Lives in the menu bar, not the Dock.
- **Codex, Claude Code, and Gemini CLI** side by side: usage limits and reset times where the tool reports them, and daily token and request activity.
- **Activity by model.** See which models today’s tokens and requests went to — any model, including ones released after this version.
- **Pick your providers.** Turn each one on or off in Settings › Providers. A provider that’s off is never refreshed and never read from disk.
- **Desktop widget.** Small and medium widgets showing what’s left at a glance.
- **Local-first.** Your usage data stays on your Mac.
- **Open source** under the MIT License.
- **No accounts required.**

## Building

Requires macOS 15 or later and Xcode 26 or later.

Clone the repository, open `UsageNow.xcodeproj`, and run the **UsageNow** scheme. The UsageNow symbol appears in the menu bar; click it to open the popover.

From the command line:

```sh
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow build
xcodebuild -project UsageNow.xcodeproj -scheme UsageNow test
```

### Data sources

- **Codex:** limits and plan come from the official Codex CLI’s app-server (`codex app-server`, `account/rateLimits/read`), which UsageNow runs locally. The app-server authenticates itself, so UsageNow never reads Codex credentials. If it’s unavailable, UsageNow falls back to the latest limits recorded in `~/.codex/sessions` and marks them as stale.
- **Claude Code:** activity comes from `~/.claude/projects`, and the plan from `~/.claude.json`. Only timestamps, identifiers, model names, and token counts are extracted. Prompts, responses, and code are never stored, logged, or sent anywhere.
- **Claude usage limits:** experimental and off by default — see below.
- **Gemini CLI:** activity comes from the session recordings Gemini CLI writes to `~/.gemini/tmp/<project>/chats/`. Only message identifiers, timestamps, model names, and token counts are extracted; prompts, responses, thoughts, and tool calls are never decoded. See below.

UsageNow honors `CODEX_HOME` and `CLAUDE_CONFIG_DIR` when they’re set.

### Team plans

UsageNow shows the plan of the account signed in on this Mac, and only that account’s own usage. For Claude Team and Enterprise it adds the seat — for example **Team · Premium** — from Claude Code’s cached profile; for Codex it reads the plan the app-server reports, even when rate limits aren’t available. Limits appear exactly when the provider returns them for your session; when it doesn’t, UsageNow says so and keeps showing activity, without estimating anything. It never asks for organization or admin credentials and never shows other members’ usage.

Team support is built from the fields these tools document and cache, and hasn’t yet been checked against a live Team account. If your plan shows incorrectly, please open an issue with the plan label you expected.

### Claude Code usage limits

Claude Code does not currently expose subscription limits through a supported local API. UsageNow can optionally read the existing Claude Code access token from macOS Keychain and query Anthropic’s usage endpoint. This integration is experimental and may require launching Claude Code in Terminal periodically to refresh your session — the Claude app keeps its own sign-in and doesn’t renew the one in your keychain.

**UsageNow never modifies or stores your Claude Code credentials, and never uses your refresh token.**

**No macOS prompt appears — turning on the setting is your consent.** Claude Code saves its sign-in with macOS’s `security` tool, and every save resets which apps may read the item, so reading it through the Keychain API would ask for your login password after each renewal, even after **Always Allow**. UsageNow reads it the way Claude Code itself does, with `/usr/bin/security find-generic-password`, which the item already trusts. The output goes through a pipe into memory; only the access token and its expiry are kept, nothing is written to disk or logged, and the token is sent only to `api.anthropic.com`.

Claude Code’s saved sign-in lasts a few hours and is renewed only when Claude Code itself runs. UsageNow picks up a renewed sign-in on its own: while the saved one is unusable, it checks only when the keychain item last changed — which reads no secret and never shows a prompt — and reads the token again once Claude Code has saved a new one. After you use `claude` in Terminal, limits come back on the next refresh, with no **Try Again**. UsageNow doesn’t run Claude Code itself.

Turn it on in **Settings › General › Fetch Claude usage limits**. When limits can’t be fetched, UsageNow says why in one line — the session needs refreshing, keychain access was denied, or Anthropic’s endpoint didn’t answer — and keeps showing local token, request, model, and plan data. The last limits it did read stay on screen for a day, marked stale, even across quitting or updating the app, so a sign-in that expires overnight doesn’t leave an empty panel in the morning. A window that reset since then keeps its row without a percentage (“Reset Mon 22:59 · not updated since”), because nothing says how much of the new window is used.

Independently of that setting, when Claude Code stops a request because a limit was reached, it records the window and its reset time in the session transcript. UsageNow shows that window as used up until it resets. This needs no sign-in and also works when you use Claude Code inside the Claude app, whose sign-in UsageNow can’t read.

### Gemini CLI

UsageNow detects Gemini CLI from its data folder, `~/.gemini`, or an installed `gemini` executable. It reads one setting — which sign-in method is configured — and checks only whether a saved Google sign-in exists. It never opens credential files and never talks to Google.

Gemini CLI doesn’t record usage limits locally, and its quota service needs the Google sign-in, so **UsageNow shows no limits for Gemini CLI** — the card says limits are unavailable and shows today’s tokens, requests, and models. The “Gemini CLI usage” menu bar mode shows the icon until a limit exists.

Google no longer lets personal Google accounts sign in to Gemini CLI; it still works with a Gemini API key, Vertex AI, or Gemini Code Assist Standard and Enterprise.

### Roadmap providers

Antigravity, DeepSeek, and Qwen are listed in Settings › Providers as **Coming soon**. They’re labels only: no integration, no credentials, and no network or file access.

Antigravity CLI (`agy`) keeps its limits only in memory, and Google’s quota service answers only Antigravity’s own clients; asked by any other app with the same sign-in, it refuses. UsageNow won’t impersonate Antigravity to get around that, so Antigravity stays on the roadmap until it offers a way to read usage.

## Desktop widget

UsageNow ships a WidgetKit extension with small and medium sizes.

- **Small** is a glance: each enabled provider’s tightest window — the one with the least left — plus the next reset. With a single provider it expands to show the window name and reset time.
- **Medium** gives each provider a column with its windows, remaining percentage, and reset times. With three or more providers it switches to one row per provider, so each stays readable.
- With more providers than fit, the ones closest to a limit are shown. Model details stay in the app.
- Disabled providers never appear, quota that isn’t available reads “Usage limits unavailable”, and old data stays visible with an “Updated … ago” note. No placeholder or fabricated values.

**The widget never touches providers.** It can’t read `~/.codex`, `~/.claude`, or `~/.gemini`, open the keychain, run `codex app-server`, or call Anthropic. The main app publishes a sanitized snapshot to a shared App Group container, and the widget only renders that. The provider and credential code isn’t compiled into the widget target at all.

### Signing and the widget

The widget reads from an App Group, which needs a signing team. Signing settings live in a git-ignored `Config/Local.xcconfig`:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# then set DEVELOPMENT_TEAM to your team ID
```

Without it, UsageNow builds ad-hoc and works normally; the widget just shows “Open UsageNow to load usage data.”

### Trying different states

Real providers run by default. For development, mock providers accept a scenario at launch: `normal`, `high`, `critical`, `unavailable`, `notInstalled`, `notAuthenticated`, `failing`, or `loading`.

```sh
open UsageNow.app --args -UsageNowMockCodex critical -UsageNowMockClaude failing -UsageNowMockGemini normal
```

The shared scheme includes these as disabled launch arguments, which you can enable under **Product › Scheme › Edit Scheme › Run › Arguments**. SwiftUI previews cover the same states without running the app.

## Architecture

```
Shared/         Code in both the app and the widget: provider catalog,
                usage models, formatters, widget snapshot, widget views
UsageNowWidget/ The extension itself: entry point and timeline provider
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
- **`WidgetSnapshotWriter`** is the only path from provider data to the widget. It drops disabled and not-installed providers, copies each display field explicitly, writes atomically, and reloads timelines only when the content changed.
- **Telemetry** is opt-in and off by default. Clients only receive a small set of events (install, daily active, updated, and whether Codex, Claude Code, or Gemini CLI is installed) with the app version, macOS version, and a random installation ID. They never have access to provider data. No analytics server is configured yet, so nothing is sent.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

UsageNow source code is licensed under the MIT License. The UsageNow name, logo, icon, and other brand assets are not covered by the MIT License.

See [LICENSE](LICENSE).
