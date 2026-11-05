# UsageNow 1.1.0

Released November 5, 2026. Native macOS app, widgets and CLI for Apple silicon and Intel; macOS 15 or later.

- **Overview:** a separate native window for today, seven days, or thirty days,
  filtered by provider, account and account set. Daily numeric model aggregates
  reuse the existing session readers. Local estimates, reported spend, credits
  and token counts keep their own labels and units. Missing history is unknown.
- **Account sets:** All accounts, Work, Personal and custom named selections,
  with independent ordering and a menu-bar account. Sets filter the interface;
  enabled sources continue updating and notifying. Following widgets use the
  active set, while personalized widgets and the CLI retain the full safe snapshot.
- **Separate menu bar icons:** choose up to four provider/accounts under
  Settings > Menu Bar > Provider icons. Each has its own monochrome icon and
  most critical current limit, following Remaining/Used. Reorder the choices;
  clicking an icon puts that account first in the shared popover. Cached data
  carries a clock, and expired windows become unknown. The UsageNow icon stays
  the default and returns when the current set has no selected available sources.
  All icons share the existing provider runtimes and refresh scheduler.
- **Adaptive refresh:** per-account scheduling, slower checks for unchanged,
  unavailable and failing sources, offline pause, screen-lock/power awareness,
  and provider cooldowns. Fixed/manual choices survive an upgrade. Fresh installs
  default to Adaptive. No process inspection or agent/session monitoring.
- **Balance and budgets:** optional per-account low money, credit and character
  thresholds, with 80%/100% daily/monthly budget notices for reported spend.
  OpenRouter's documented UTC day/month counters support budgets initially;
  providers exposing only a balance support low-balance notices. Quiet hours
  consume alerts, and notification memory survives relaunch. Budgets do not
  block spending, and local API-price estimates never become reported spend.
- **MiniMax:** explicit global M Plan subscription key, verified by a read-only
  request to `www.minimax.io/v1/token_plan/remains`, stored only in Keychain.
  Reported quota windows and reset times appear in the menu bar and widgets;
  multiple accounts use the existing connection flow. Off by default.
- **Thirteen languages:** new interface and bundled release notes translated
  into all existing languages, including the requested Uzbek Ö/Ğ/Ş/Ç spelling.

## MiniMax validation boundaries

The parser is checked against the official API/CLI schema and synthetic fixtures.
A live paid M Plan account has not been used for this candidate. Legacy remaining
counters and newer consumed counters are reconciled with explicit percentages.
Inconsistent readings and boosted allowances with an ambiguous denominator keep
their percentage unknown; unlimited weekly buckets are not shown as exhausted.
The first integration targets global M Plan, not PAYG balance or regional web sessions.

References: [MiniMax M Plan FAQ](https://platform.minimax.io/docs/m-plan/faq),
[official CLI quota types](https://github.com/MiniMax-AI/cli/blob/main/src/types/api.ts),
[official CLI counter semantics](https://github.com/MiniMax-AI/cli/blob/main/src/utils/quota.ts),
[OpenRouter reported UTC periods](https://github.com/OpenRouterTeam/docs/blob/main/api_reference/limits.mdx).

## Download verification

- File: `UsageNow-1.1.0.dmg`
- Version: **1.1.0 (15)**
- Developer ID signed and notarized by Apple.
- SHA-256: `9481545d4aa8600c515e8c249fa8110cbbfadae622792222dc853e0c5cf3346b`
