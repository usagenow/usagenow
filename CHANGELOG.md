# Changelog

All notable changes to UsageNow. This project follows [Semantic Versioning](https://semver.org).

## 0.5.0

### Added

- **Kiro.** A new provider with your plan's monthly credit limit, when it resets, and today's credits and prompts. Kiro offers no public way to read its limits, but it writes the answer it receives to its own log; UsageNow reads that, and makes no request of its own. The account identifiers in the same answer are never read. A free trial that has ended is ignored, so a plan with every credit left isn't shown as exhausted. While Kiro is closed, the last limits it recorded stay on screen with when they were read.
- **Warp.** A new provider with today's agent requests, credits, and tokens per model, read from Warp's local database, opened read-only. The text of prompts and replies is never read. Warp keeps one running credit total per conversation, so a conversation that began before today is left out and today's credits are marked partial rather than overstated. No usage limit is shown: the one in Warp's settings still describes its earlier request-based plans.
- **DeepSeek, Kimi, and OpenRouter, with your own API key.** Each shows what its official API reports: DeepSeek's balance in your account's currency, Kimi's available balance, and OpenRouter's spending today and this month, with the key's limit as a window when it resets. Add a key in **Settings › Providers**. The key is kept only in this Mac's Keychain, sent over HTTPS only to that provider's host, and deleted when you turn the provider off. Redirects aren't followed and answers from other hosts are refused, so the key can't be passed on. These providers start off. All three follow their documented responses but are not yet verified against live accounts.
- **Credits today** for tools that meter in credits, and a **Monthly** limit window.

### Fixed

- **Sparkle's license notice** is now in **About › Open Source Licenses**. It was missing from 0.4.0.

## 0.4.0

### Added

- **What today's tokens would cost.** Each provider shows an estimate beside its token and request counts — "≈ $4.20 at API prices" — of what the day's activity would have cost had it been billed through the API. Your subscription doesn't charge per token, so this is a sense of scale, not a bill. Cached tokens are priced as cached: on Claude Code most of the volume is cache reads at a tenth of the input price, so counting everything at the input rate would overstate a day sevenfold. A model with no published price isn't counted at all, and the line says the estimate is partial instead of quietly leaving it out. Prices ship with the app and are refreshed each release.
- **Updates in the app.** UsageNow can now check for updates and install them, through Sparkle. **Settings › General** has the switch and a Check Now button. An update is installed only when it carries UsageNow's signature, and checking sends nothing about you — no identifier and no system profile. A build that wasn't made by the release process, such as one you build yourself, can't update itself at all. Coming from 0.3.0, install this version by hand once; later versions arrive on their own.

### Changed

- **Refresh shows progress instead of spinning.** The button is an arrow at the weight of the settings gear beside it, and while a refresh runs an arc sweeps around it.
- **The menu bar percentage is sized to the icons around it**, rather than to the menu bar's own larger text, so it no longer stands out from its neighbours.

## 0.3.0

### Added

- **Gemini CLI.** A new provider, with the same enable, refresh, menu bar, widget, and telemetry behavior as Codex and Claude Code. Activity and models come from Gemini CLI's local session recordings. Gemini CLI records no usage limits locally, so none are shown. Credential files are never opened.
- **Antigravity.** A new provider with usage limits, and the same enable, refresh, menu bar, and widget behavior. Limits from the Antigravity app itself: while it runs, UsageNow reads the loopback port and CSRF token the app prints in its command line, then asks its language server for the quota summary its `/usage` panel shows — 5-hour and weekly windows per model group, plus the plan. No credentials are read or sent, and nothing leaves `127.0.0.1`. Between runs the last limits stay for a day, marked stale. (The Antigravity CLI's own server can't be read, so the app must be running.)
- **Activity by model.** A compact **Models today** list in each provider's section shows tokens and requests per model, most active first. It works for any model identifier, including ones released later, and never shows a percentage: account limits aren't split by model. Available for Claude Code, Codex, and Gemini CLI.
- **Team plans.** Claude Team and Enterprise show the member's seat, such as **Team · Premium**. Codex reads the plan from `account/read`, so Team, Business, and Enterprise accounts show their plan even when rate limits aren't returned, and newer billing variants map to their plan name. Not yet verified against live Team accounts.
- **Gemini CLI usage** and **Antigravity usage** menu bar modes. Gemini CLI's shows the icon while it reports no limits.
- **Reorder providers.** Drag providers in Settings › Providers, or use Move Up and Move Down; the popover and widget follow that order.
- **Cursor** and **GitHub Copilot** are listed as Coming soon.

### Changed

- The medium widget shows one row per provider when three or more are on; the small widget lists up to three. When not everything fits, providers closest to a limit win. Windows of the same length from one provider carry their scope, such as "Weekly · Opus".
- A provider added in an update starts on once, as it would for a new user. Providers you turned off stay off.

### Fixed

- **No more login-password prompts for Claude limits.** Claude Code saves its sign-in with macOS’s `security` tool, and every save resets which apps may read it, so 0.2.0 asked for the login password after each renewal, even after **Always Allow**. UsageNow now reads the sign-in the way Claude Code does, with `/usr/bin/security`. Turning on the setting is the consent; the token is still kept only in memory.
- **Claude limits come back by themselves after Claude Code renews its sign-in.** 0.2.0 stopped reading the keychain after an expired sign-in until you chose **Try Again**, so a sign-in renewed by running `claude` went unnoticed. UsageNow now watches when the keychain item last changed — reading no secret and showing no prompt — and reads the new sign-in on the next refresh.
- **Last known Claude limits survive quitting and updating the app.** They were kept in memory only, so installing an update overnight left an empty panel in the morning. Percentages and reset times — never credentials — are now stored locally for up to a day, and removed when the setting is turned off.
- **A Claude window that reset after the last reading stays on screen.** It used to disappear, so an old reading showed only the weekly limit. It now shows as "5-hour —" with "Reset Mon 22:59 · not updated since", and the way to refresh stays visible.
- **Claude limits you hit show up without a sign-in.** When Claude Code stops a request at a limit, it records which window and when it resets; UsageNow reads that from the transcript and shows the window as used up until then — also when the experimental source is off, or when you work in the Claude app, whose sign-in UsageNow can't use.
- **UsageNow no longer runs `claude auth status` when the Claude sign-in expires.** 0.2.0 did, expecting the CLI to renew its sign-in; on current versions it exits successfully without renewing, so it only started a process for nothing.

## 0.2.0

### Added

- **Real provider data.** Codex usage limits, reset times, and plan come from the official `codex app-server`, with the latest limits recorded in local sessions as a stale fallback. Token, request, and model activity for both Codex and Claude Code comes from local session files.
- **Desktop widget.** Small and medium WidgetKit widgets. The small size shows each provider's tightest window plus the next reset; the medium size gives each provider a column of windows. The widget renders a sanitized snapshot the app publishes to an App Group — it never touches providers, files, the keychain, or the network.
- **Providers settings.** Codex and Claude Code can be tracked independently, both on by default. A disabled provider is never refreshed or read from disk. Gemini CLI, DeepSeek, and Qwen are listed as roadmap entries.
- **Claude usage limits (experimental, off by default).** Reads the existing Claude Code sign-in from the keychain and asks Anthropic's usage endpoint. When the saved sign-in has expired, UsageNow asks the Claude Code CLI to renew it and reads the keychain again; it never refreshes, rotates, or writes credentials itself.
- **Appearance setting** — Light, Dark, or System — with Light as the default.
- **Menu bar display modes:** icon only, most critical usage, or a specific provider.
- **Telemetry foundation:** anonymous installation identity, a small event set, and a network client. Off by default, and no endpoint is configured yet, so nothing is sent.
- **Localization readiness** through a String Catalog, with numbers formatted to match the UI language.

### Changed

- Usage is shown as what's left ("58% left"), and bars shrink as usage grows.
- Quota windows are whatever a provider reports — an account may have only a weekly window — and a missing window is never invented.
- When quota can't be fetched, UsageNow says why in one line instead of a blanket message.
- A quota that can't be read right now — an expired sign-in, a denied keychain, an endpoint that didn't answer — no longer blanks the display. The last known limits stay for a day, shown as stale, so an overnight expiry doesn't leave an empty menu bar in the morning. Only an account that genuinely has no limits clears them.

## 0.1.0

- First milestone: native menu bar app with mock providers, settings, states, and tests.
