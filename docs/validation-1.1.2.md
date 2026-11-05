# UsageNow 1.1.2 validation

## Observed regression

On macOS 27.0.1 (26A434), the installed app and widget were 1.1.1 (16), but the live widget process mapped an older executable UUID. Menu bar readings updated while the existing widget stayed at 81% and "Updated 10m ago". Restarting that extension let WidgetKit accept a fresh timeline, but Notification Center rejected its archive with `bundleStubNotSupported` / `Widget extension could not be looked up`. The user restored rendering by removing and adding the widget.

This separates three checks: a new snapshot, an accepted timeline, and an actually rendered widget. None proves the next one by itself.

## Change

- Once per installed build, retire the owned extension, register the installed app and extension, and issue two bounded timeline reloads after registration settles. A failed registration is retried on the next app launch.
- Before a future in-app update replaces the bundle, retire the extension through the updater's postponement callback. Completion always resumes installation.
- Match executable, process owner and start time before sending SIGTERM. A relocated updater process additionally requires the production widget identifier and the app's Developer ID team. Never signal NotificationCenter or chronod, delete caches, or reset widget placements.
- If the old executable has already been deleted, query only its recorded executable name with `ps -o comm=`. This fallback is limited to the current user's `UsageNowWidget`; the exact installation path and unchanged process birth time are still required. No arguments, environment or process memory are read.
- Development, archive, export and mounted DMG copies cannot take over the production registration. An ordinary relaunch of the same installed build does not restart the widget.
- Use native SwiftUI time data with minute precision for widget age labels. No additional provider request or per-second timeline reload is introduced.

## Acceptance gates

- Full regression suite, including a controlled child-process retirement check.
- Signed universal app/widget/CLI and matching build/App Group metadata.
- Upgrade from installed 1.1.1 with an existing widget; verify extension identity, accepted timeline and visible content separately.
- Apple notarization and stapling, DMG hash, update signature and public download/appcast checks before publication.

Intel runtime, older macOS runtime and every previously broken widget configuration remain outside the scope of this Mac's live acceptance. An already damaged widget may still need to be added again once; do not claim a universal system-cache repair.

## Local acceptance results

- 652 tests passed, with no failures or skips, on native arm64 macOS. Result bundle: `Widget-1.1.2-final-tests-4.xcresult`.
- The first local candidate (build 17, never published) exposed another real upgrade case: Sparkle had deleted the previous executable, so `proc_pidpath` and Security's dynamic code lookup could no longer resolve it. Registration completed, but the old process remained. Build 18 adds the narrow launch-path fallback; a read-only check against that same process confirmed it is recognized.
- Installed build 18 through the official Sparkle CLI using a loopback-only test appcast and the production update key. This exercised a real bundle replacement with the old 1.1.1 widget process still alive. The new app retired it, registered its extension and loaded fresh timelines without deleting or adding any widget.
- The running extension's arm64 UUID matched the installed build (`03735569-F541-3543-B595-DA36159F05B5`). Notification Center reported `Content load successful` and `LIVE`; the user confirmed that the existing widget displayed data. The CLI test covers startup recovery, not the app UI's new pre-install delegate callback.
- App, widget and CLI are universal and Developer ID signed. Apple accepted and stapled the app (`d35afd5f-d0fe-4d6f-9421-66027bf124ae`) and DMG (`c31469e9-589d-4c08-a4b4-b5df6fd5764b`). Gatekeeper accepted both.
- DMG: 6,145,555 bytes; SHA-256 `a5e6c51144d7ffb28431230b852285134b9d903e8afc73c725013ce09553efbb`. Its Ed25519 signature was independently verified with the installed app's public key.
- Site and docs `npm run check` passed, including build, type checking, lint, locale/navigation/server checks and documentation links.

## Publication verification

- GitHub release `v1.1.2` is public and points to source commit `d0bfdb2a04c6d417d8febe94207232a78d48bfa9`. The downloaded DMG and checksum match the accepted artifact above.
- Site commit `623f1023abf99d0fb718bb16954b36b245eae400` and docs commit `bff109aabfa94d949571c7ebdc3f070c0c0445b3` were built and checked in staging before promotion. Both services are online; previous deployments were retained for rollback.
- Public checks passed for 52 site pages across 13 locales, 7 documentation pages and 10 static assets. The stable download redirects to `https://usagenow.com/download/UsageNow-1.1.2.dmg` and its bytes match the release checksum.
- The production appcast contains build 18 first and preserves all 7 earlier releases. The public DMG signature was independently verified against the installed app's public key. A probe with the official Sparkle CLI and a 1.1.1 bundle found the update through `https://usagenow.com/appcast.xml`.
- The user is running the accepted build 18 locally. The temporary loopback feed server is stopped; the installed application uses the production appcast.
