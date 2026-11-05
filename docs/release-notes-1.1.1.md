# UsageNow 1.1.1

November 5, 2026. Hotfix, build 16. macOS 15 or later.

- Fixed a freeze and runaway memory use when enabling Provider icons in Settings > Menu Bar, including launching with this mode already selected.
- Provider logos use a fixed intrinsic size in the menu bar. Antigravity uses its official transparent monochrome artwork instead of the old opaque PNG.
- The display clock remains separate from provider refreshes. Selected accounts and their order are preserved.

Validation includes a regression scenario running the actual menu bar scenes with isolated fixture data and an external main-thread watchdog. MiniMax paid-account validation remains pending, as in 1.1.0.

## Download verification

- Developer ID signed and notarized by Apple.
- File: `UsageNow-1.1.1.dmg`
- SHA-256: `65e12c1c947f16850e404ea719f8966a8a5eae7c67d37f55b127b858000cac99`
