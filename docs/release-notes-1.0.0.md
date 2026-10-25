# UsageNow 1.0.0

Requires macOS 15 or later. Universal for Apple Silicon and Intel, Developer ID
signed and notarized by Apple. Existing installations retain their settings.

- Kazakh, Uzbek and Turkish across the app and widgets: thirteen languages. Uzbek copy uses Ö, Ğ, Ş and Ç as specified for this localization.
- Optional first-run setup with provider choices. Skip it or reopen it in Settings. Existing installations keep their preferences and do not show setup automatically; no provider reads begin until first-run setup is finished or skipped.
- Per-provider notification thresholds, independent reset alerts and quiet hours in this Mac’s time zone. Quiet alerts are skipped, not queued. Stale and expired readings do not trigger low-limit alerts.
- Optional CLI: usagenow status and usagenow status --json read the app’s safe snapshot, with freshness and reset times. No provider runtime, network, authentication or history export. Install from Settings › General; shell configuration is left to the user.
- Refresh after wake, notification migration and snapshot compatibility checks. CLI output clears percentages after reported resets, preserves unknown values and rejects unsupported snapshot versions.
- Updated JetBrains AI and Perplexity icons to match the website, with light and dark appearance support.
