# Contributing to UsageNow

Thanks for your interest in improving UsageNow.

## Getting started

1. Install Xcode 26 or later. UsageNow targets macOS 15+.
2. Open `UsageNow.xcodeproj` and run the **UsageNow** scheme.
3. Run the tests with **⌘U** or `xcodebuild -project UsageNow.xcodeproj -scheme UsageNow test`.

The project uses Xcode’s folder-synchronized groups, so new files in `UsageNow/` or `UsageNowTests/` are picked up automatically.

## Guidelines

- **Native first.** Use SwiftUI, system colors, and SF Pro. The app must look right in light and dark mode and with increased contrast.
- **Views depend only on normalized state.** Provider-specific logic belongs in a `UsageProvider` implementation, never in views.
- **Keep it simple.** Add protocols at meaningful boundaries (providers, telemetry, secure storage), not for every small service.
- **Swift 6 concurrency.** Keep UI state on the main actor and use async/await. Don’t add Combine without a strong reason.
- **No new dependencies** without discussing them in an issue first.
- **Privacy is non-negotiable.** Provider data must never reach telemetry, and nothing is sent over the network without explicit design review.
- **Test non-UI logic.** Normalization, thresholds, formatting, provider parsing, and store behavior all have unit tests (Swift Testing). Add tests alongside changes.
- **Fabricated fixtures only.** Test data must be synthetic. Never commit real prompts, code, credentials, usernames, project names, session IDs, or account identifiers — and never samples copied from your own `~/.codex` or `~/.claude`. Tests must not depend on the developer’s real account.
- **Localization.** User-facing strings live in `UsageNow/Resources/Localizable.xcstrings`. Xcode updates it when you build in the IDE; after command-line builds, run `scripts/sync-strings.sh`. Don’t localize product names (UsageNow, Codex, Claude Code).

## Pull requests

- Keep each PR focused on one change.
- Make sure the project builds without warnings and all tests pass.
- For UI changes, include light and dark screenshots.

## Brand assets

The UsageNow name, logo, icon, and other brand assets aren’t covered by the MIT License. Please don’t use them in forks or derived products in a way that suggests an official affiliation.

By contributing, you agree that your contributions are licensed under the MIT License.
