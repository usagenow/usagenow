# UsageNow 1.1.2

November 5, 2026. Widget hotfix, build 18. macOS 15 or later.

- Improved recovery of existing widgets after an app update, preserving their selected accounts and placement.
- Widget update-time labels keep advancing while macOS delays the next refresh.

The installed app refreshes its widget registration once per build. Its updater also retires the previous UsageNow widget process before replacing the bundle. This does not reset Notification Center, delete widget caches or change provider connections. Widgets continue to render only UsageNow's sanitized local snapshot.

If a widget was already stuck before updating, remove and add that widget once. UsageNow settings and provider connections are retained.

Developer ID signed and notarized by Apple.

SHA-256: `a5e6c51144d7ffb28431230b852285134b9d903e8afc73c725013ce09553efbb`
