# UsageNow 1.1.0 acceptance

Scope: local candidate validation and the production release authorized on November 5, 2026. The local candidate below is retained as historical evidence; it is separate from the final production DMG. Manual interactive acceptance and live MiniMax validation are not claimed.

## Production release

- Version **1.1.0 (15)**; app, widget and CLI are universal and Developer ID signed.
- App and DMG notarized and stapled; Gatekeeper accepts both as Notarized Developer ID.
- Update public key matches the installed 1.0.0; the configured opt-in telemetry endpoint is restored.
- DMG SHA-256: `9481545d4aa8600c515e8c249fa8110cbbfadae622792222dc853e0c5cf3346b`; size **6073110 bytes**.
- Published GitHub tag/release: `v1.1.0`, app source `bd71410`; the downloaded GitHub asset matches the final SHA-256 and verifies with the installed app's public key.
- Site `fa3c868` and docs `a29e90d` deployed to their named Hetzner services; both online, rollback copies retained.
- Public verification passed for 52 site pages across all 13 languages, six docs pages, ten static assets, MiniMax artwork, and the six-entry appcast.
- Stable download redirects to `https://usagenow.com/download/UsageNow-1.1.0.dmg`; the downloaded site image matches the final SHA-256.
- The appcast offers build 15, minimum macOS 15.0, and the verified EdDSA signature. This verifies update eligibility and download integrity, not an interactive installation on this Mac.
- Site checks: 312 localized pages, 17 navigation/history tests and seven static-server tests. Docs checks: 4,392 valid internal links across 42 pages and six server tests. All passed.

## Local candidate result

- Version **1.1.0**, build **15**. Xcode: **638 passed, 0 failed, 0 skipped**.
- App, widget and CLI are universal `x86_64 arm64`, Developer ID signed with
  hardened runtime and no debugging entitlement. Production App Group matches.
- `build/Local-1.1.0/UsageNow-1.1.0-local.zip`, **5,691,643 bytes**.
- SHA-256: `835fe0bb2e62896393c86d88fc90b81c48f7733ca33d3ae800344e7b4aa6ae29`.
- ZIP integrity, version metadata, CLI `--version`, bundled MiniMax artwork,
  signatures, App Group and empty update/analytics configuration verified.
- The installed `/Applications/UsageNow.app` remains **1.0.0**. Candidate not
  installed or notarized. Manual checks below and live MiniMax validation remain.
- Machine-readable receipt: `build/Local-1.1.0/verification.json` (not committed).
- Passing result bundle: `build/Development-1.1.0/MenuBar-1.1.0-unsigned-tests.xcresult`.

## Automated checks

- Sets: persistence, ordering, empty sets, renamed/deleted/disabled accounts,
  menu-bar isolation and follow-app versus explicit widget selection.
- Menu bar icons: legacy display migration, persisted mode/order, a four-account
  cap, deduplication, deletion without silently changing accounts, set/enable
  filtering, empty/missing-source fallback, per-account values, scoped windows,
  expiry, unknown/future data, stale-cache markers and account-focused popovers.
- Overview: today/7/30-day bounds, model aggregates, unknown history, credits
  versus tokens, and exclusion of yesterday's cached and future activity.
- Scheduling: independent source due times, offline/lock/low-power modes,
  unchanged content, cache repeats, backoff, cooldown/wake and preference migration.
- Finance: actual counters only, account currency, UTC boundaries, unknown
  calendars, stale/future/failing readings, 80/100% deduplication, top-ups, quiet
  hours and persisted notification memory.
- MiniMax: remaining-versus-consumed semantics, contradictory/boosted data,
  missing/unlimited buckets, rejected keys, no-key network isolation and read-only
  single-host credential verification.
- Existing provider, widget, CLI, consent, notification and update suites.
- New strings in thirteen languages; offscreen English/Russian/Hebrew views
  in light/dark appearances, including menu bar settings and provider labels.
  These images are layout checks, not proof of
  interactive navigation, notification delivery or real subscription access.
- XCTest runs use `CODE_SIGNING_ALLOWED=NO`, matching the earlier passing test
  configuration. Signed test-host launches stalled in the system loader before
  establishing a test connection; this does not count as a passing test run.
  The final universal Release app is signed and verified separately.

## Manual check on the candidate

1. Upgrade from 1.0: accounts, language, fixed refresh interval, notification
   consent and widget selections remain. No first-run prompt after upgrade.
2. Open Overview from the menu bar and shortcut panel. Switch date ranges,
   providers and accounts; resize the window, scroll, and check light/dark/RTL.
   Under Settings > Menu Bar choose Provider icons. Check up to four separate
   items, reorder/rename sources, open each account, and return to UsageNow icon.
   Check the Settings/Overview buttons and shortcut with the brand icon hidden.
   Switch to an empty set or disable selected providers: the fallback icon
   must appear. A quota reset must not leave an expired percentage in the bar.
3. Create Work/Personal/custom sets, reorder and rename accounts, delete one,
   change the menu-bar source. Following widgets change; explicitly configured
   widgets keep their selections; `usagenow status --json` keeps all enabled sources.
4. Enable Adaptive. Check wake, network disconnection/recovery, screen lock and
   low-power mode. Manual refresh must still respect provider rate limits.
5. Set low-balance/credit/character rules on a connected account. Configure
   OpenRouter daily/monthly budgets, check quiet hours, restart and period rollover.
   Notifications remain opt-in and require system permission.
6. Connect MiniMax with an M Plan subscription key in Settings. Verify the live
   plan's reported windows/reset times against the MiniMax usage page. Never
   paste credentials into reports or chat. Unsupported boosted percentages stay unknown.
7. Confirm production 1.0 widgets after replacement, plus the bundled CLI link,
   on macOS 15+ and current macOS. A universal build is not an Intel runtime test.

The local build is signed for upgrade/widget testing. Apple notarization and
publication are separate release steps after manual acceptance.
