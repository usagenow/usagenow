# Changelog

All notable changes to UsageNow. This project follows [Semantic Versioning](https://semver.org).

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

## 0.1.0

- First milestone: native menu bar app with mock providers, settings, states, and tests.
