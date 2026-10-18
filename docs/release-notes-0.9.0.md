# UsageNow 0.9.0

Personal widgets, a clearer view of quota consumption, and Dutch localization.

## What's new

- **Personal widgets:** choose providers and accounts separately for each widget. Leave the selection empty to follow the app.
- **Large widget:** up to four detailed provider/account rows with reported limits and reset times.
- **Quota pace:** a local chart and a clearly labelled estimate based on fresh quota observations, never token counts. Insufficient data, stale readings, resets and unknown window lengths suppress the estimate.
- **Optional service incidents:** public OpenAI, Claude, Cursor and GitHub Copilot status indicators. Off by default, separate from account connection errors.
- **Antigravity CLI fallback:** when the IDE cannot answer, compatible official `agy` CLI 1.x versions (1.1.11+) can supply the read-only usage report. Verified with 1.2.2; no agent request or credential access by UsageNow.
- **JetBrains AI (experimental):** local AI Assistant quota and reported refill dates in the menu bar and widgets. Reads quota XML and newer quota events from the same IDE, without credentials or network requests. Active-subscription validation remains pending.
- **Dutch / Nederlands:** app, widgets, bundled release notes and website. UsageNow now supports ten languages.
- **Updated Windsurf and ElevenLabs icons** for light and dark appearances.

## Privacy and limitations

Widgets remain snapshot-only renderers: no credentials, provider files or network clients. Quota history stays on the Mac and never enters telemetry. Optional analytics remain opt-in. JetBrains AI uses internal local formats and does not report token activity, top-up credit counters or organization-wide analytics. Existing Claude authentication limitations are unchanged.

Requires macOS 15 or later. Universal app for Apple Silicon and Intel.
