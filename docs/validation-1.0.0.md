# UsageNow 1.0.0 validation

Local candidate; distribution is pending maintainer acceptance. Keep paid and
Team integrations marked experimental until checked against real accounts.

## Final DMG verification — 2026-10-25

- Rebuilt from the preserved 1.0.0 sources after the requested build cleanup:
  **590 tests passed, 0 failed, 0 skipped**.
- Final artifact: `build/Release-1.0.0-Final/UsageNow-1.0.0.dmg`, **1.0.0 (13)**,
  **5,029,211 bytes**. SHA-256:
  `2ecae9d0b754651e6621646689be7e7c5835f685ea793256d55644f8020bad98`.
- App, widget and CLI are universal arm64/x86_64, Developer ID signed with
  hardened runtime and the matching production App Group. App/widget versions
  match; no debugging entitlement is present.
- Apple accepted the app (`76844d4d-98ee-4c82-9fa2-a58fefa7587b`) and DMG
  (`36bedb88-8481-4866-820a-810260b7cb99`). Both tickets were stapled and
  validated. Gatekeeper accepts both as `Notarized Developer ID`.
- Mounted the final DMG read-only without Finder or launching the app. Verified
  the embedded app's ticket/signature and compared app, widget and CLI binaries
  with the exported build. The image checksum is valid.
- The image contains UsageNow.app and an Applications symlink. Its stored window
  is 520×360, with a solid #e2e7ee background and 112-point icons at the agreed
  positions. Headless packaging settings, scripts and pinned dependencies are
  retained beside the final DMG; they are build-only, not part of the app.
- Installed `/Applications/UsageNow.app` remains **0.9.0**. No installation,
  GitHub publication, website/docs deployment or appcast change was performed.
- Maintainer's installation, widget, connection, notification and language checks
  remain the acceptance gate before publication. Earlier ZIP candidates were
  removed in the requested cleanup and are superseded by this DMG.

## Local verification — 2026-10-24

- Debug application test suite: **590 passed, 0 failed, 0 skipped**.
- Website checks: typecheck, lint, static build, **13 languages / 312 pages**,
  **92 text groups / 37 FAQ answers per language**, 17 navigation tests and
  7 static-server tests passed.
- Documentation checks: typecheck, lint, static build, internal links and
  6 static-server tests passed.
- Rendered native setup and notification screens in Kazakh, Uzbek, Turkish,
  Russian and Hebrew. Browser-checked the three new website languages,
  language ordering, a 390-pixel layout and back/forward navigation.
- JetBrains and Perplexity use the website's exact SVG geometry, with inline
  paint attributes for the native asset compiler. JetBrains retains its brand
  colors; Perplexity is a template image. Both were rendered in light and dark.
- These checks do not replace real-account, overnight widget, macOS 15,
  Intel hardware, VoiceOver or native-speaker acceptance testing below.
- Release candidate **1.0.0 (13)**: app, widget and CLI contain both arm64 and
  x86_64, use Developer ID / hardened runtime, share the production App Group,
  and have no debugging entitlement. The release build verification passed.
- Apple accepted the candidate app; its ticket is stapled and validated, and
  Gatekeeper reports `Notarized Developer ID`. The candidate is packaged at
  `build/ReleaseCandidate-1.0.0-Icons/UsageNow-1.0.0-candidate.zip` for local testing,
  including the refreshed JetBrains and Perplexity logos.
  It has not been installed or added to an update feed.

## Automated coverage

- Preference migration: existing notification consent, default thresholds,
  skipped/completed setup, and existing installations.
- Quiet hours: daytime, overnight, exact boundaries, current time zone,
  consumed alerts and no morning backlog.
- Snapshot/CLI: schema version, unknown values, expired resets, stale readings,
  malformed input, and explicit display fields only.
- Existing widget, provider, connection, quota-cache and activity suites.
- App/widget localization and placeholder coverage; website locale, navigation,
  static generation and server checks.

## Manual acceptance before distribution

- Upgrade from 0.9.0: no automatic setup; accounts, language, widget selections,
  opt-in settings and the installed CLI link survive.
- Fresh installation: setup can be skipped/closed; it starts no provider reads
  before completion. No sign-in, Keychain or notification prompt on its own.
- Enable notifications explicitly; check one threshold, an independent reset,
  quiet hours, relaunch, sleep/wake and a time zone change. No repeated alerts.
- Check all widget sizes and account selections overnight, offline and after
  quota reset. Old percentages become unknown rather than fresh zeroes.
- Install/remove CLI through Settings. Existing unrelated commands must remain
  untouched. Check status, JSON, help, version, stale and missing-snapshot output.
- Check Kazakh, Uzbek (Ö Ğ Ş Ç), Turkish and Hebrew layouts with keyboard and
  VoiceOver. Confirm translations with native speakers before claiming review.
- Verify signed universal app + widget + CLI. Run on minimum macOS 15 and a
  current macOS on real hardware; a cross-build is not an Intel runtime test.
- After acceptance: final DMG packaging, DMG notarization, final hash and update
  signature; then approve GitHub/site/docs/appcast publication.

CSV/JSON history export, additional providers and cloud sync are outside 1.0.0.
