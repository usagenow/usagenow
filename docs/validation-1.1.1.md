# UsageNow 1.1.1 validation

## Regression and fix

On macOS 27.0.1 (26A434), the installed 1.1.0 (15) main thread repeatedly updated `MenuBarExtraHost` / `MenuBarExtraController.updateButton` and consumed 38 GB of memory after Provider icons was selected. A fixture-only runtime scenario reproduced the blocked main-thread heartbeat with the original `TimelineView` label.

A single cancellable `MenuBarClock`, owned outside label rendering, now advances at most once every 15 seconds while provider icons are visible. It does not fetch provider data. The same runtime scenario passes after the fix. The menu bar now uses actual 15-point template NSImages; Antigravity uses the official [one-color SVG](https://antigravity.google/assets/image/brand/antigravity-icon__one-color.svg), with transparent margins fitted to the icon.

## Completed checks

- 643 tests passed, zero failed/skipped. Includes clock cancellation/lifetime, all provider image sizes, and Antigravity alpha coverage.
- Real MenuBarExtra runtime: one/four icons, eight reorder/empty-set/disable/restore/mode-switch cycles, saved provider mode at startup, selection preservation and clock tick. External watchdog did not fire after the fix.
- User visually checked Codex 58%, Claude 72%, Antigravity 70%, and Cursor 83% in the system menu bar on November 5, 2026. Those were explicitly synthetic readings, with isolated preferences and no live credentials or widget publication.
- The installed 1.1.0 was recovered by switching only the icon layout to UsageNow; original selected accounts were retained.

## Reproduce the runtime check

On an interactive Mac, build Debug with `CODE_SIGNING_ALLOWED=NO`, then run:

```sh
python3 scripts/test-menubar-runtime.py build/Development-1.1.1/Build/Products/Debug/UsageNow.app
python3 scripts/test-menubar-runtime.py build/Development-1.1.1/Build/Products/Debug/UsageNow.app --start-with-provider-icons
```

Test icons briefly appear in the real menu bar. The Debug-only harness uses mock providers, separate preferences, no updater, no telemetry and no widget writer. Its watchdog kills a blocked test process promptly. It is not compiled into Release.

The signed Release app is validated separately from the unsigned Debug test host. MiniMax paid-account and Intel-runtime validation remain pending as previously documented.

## Production artifact

- Version 1.1.1 (16); app, widget and CLI universal x86_64/arm64, Developer ID signed.
- App and DMG accepted by Apple, stapled and Gatekeeper-validated.
- Update key matches installed 1.1.0; the opt-in telemetry endpoint is unchanged.
- Final DMG: 6107228 bytes; SHA-256 `65e12c1c947f16850e404ea719f8966a8a5eae7c67d37f55b127b858000cac99`.
- EdDSA signature verified with the public key read from the installed production app.
- Seven-entry appcast preserves old releases and offers build 16 for macOS 15.0+.
- Debug-only test and preview hooks are absent from the production binary.
