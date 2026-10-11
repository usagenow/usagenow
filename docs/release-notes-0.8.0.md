# UsageNow 0.8.0

Six new providers, more reliable widgets, and nine languages.

## What's new

- **Windsurf** — daily and weekly limits, reset times, and plan from its local cache. Older plans can show billing-cycle credits. No credential access or network request.
- **Cursor, GitHub Copilot, Perplexity, ElevenLabs, and Z.ai** — connect in Settings › Providers. Each account has its own usage in the popover and widget. Credit and character counters stay separate from today's local activity.
- **Cursor and Perplexity sign-in** in a temporary, isolated browser window, with a manual session-cookie fallback. Existing browser profiles are never imported.
- **Check before saving** — keys, tokens, and cookies are verified with a read-only usage request before saving to this Mac's Keychain. Errors distinguish rejected credentials, missing permissions, network problems, and unsupported responses.
- **Rate-limit cooldowns** — background refresh, manual refresh, and connection checks respect HTTP 429 and Retry-After. Other accounts continue updating; cached readings keep their original timestamp.
- **Portuguese, Japanese, Korean, and Hebrew**, alongside English, German, Spanish, French, and Russian. What's New is translated and available offline.
- **Choose an added account for the menu bar**, with a safe fallback when it is removed.

## Widget fixes

- Freshness is tracked separately for each provider; updating one no longer makes another's old reading look fresh.
- Countdown timers keep ticking between refreshes. After a quota reset, the old percentage becomes unknown until a new reading arrives.
- Fresh readings are saved even when the percentage hasn't changed.
- Development builds no longer compete with the installed app and widget for registration or their shared snapshot.

## Before connecting

The five new connections are off by default. ElevenLabs uses its official subscription API with a restricted `user_read` key. Cursor, Copilot, Perplexity, and Z.ai use **experimental endpoints** that may change; not every plan or token type is supported. Copilot uses your own GitHub token, not VS Code's identity. Perplexity reads web credits, not Sonar API usage. Z.ai supports the global Coding Plan endpoint. Embedded sign-in can be refused by some SSO providers.

Windsurf must run to refresh its local cache. UsageNow must run to fetch new data for the widget. Claude's existing credential policy is unchanged: UsageNow never refreshes, modifies, or stores Claude Code credentials.

See [connection details](https://docs.usagenow.com/providers/connections) and the [full changelog](https://github.com/usagenow/usagenow/blob/v0.8.0/CHANGELOG.md).

## Install

Download **UsageNow-0.8.0.dmg**, open it, and drag UsageNow to Applications. Existing users can choose **Settings › General › Check Now** after the update feed is live.

macOS 15 or later · Apple silicon and Intel · version **0.8.0 (11)** · Developer ID signed and notarized by Apple. Anonymous analytics remains optional and off by default.

SHA-256:

```text
ef52c77f12fd83863d56e1811eed051a33fa18a70ce46735a2a490ca19194e98
```
