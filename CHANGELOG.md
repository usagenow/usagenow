# Changelog

All notable changes to UsageNow. This project follows [Semantic Versioning](https://semver.org).

## 1.1.1

### Fixed

- Fixed a freeze and runaway memory use when switching to Provider icons in Menu Bar settings or reopening the app with that mode selected.
- Provider icons now have a consistent menu bar size. Antigravity uses a transparent monochrome mark without a white square.

## 1.1.0

### Added

- Overview — Today / 7 days / 30 days. Local activity recorded on this Mac. History may be incomplete.
- Account sets — Sets change what you see. Enabled accounts keep updating and sending notifications.
- Separate provider icons — Show selected provider icons and usage side by side in the menu bar.
- Adaptive — Adaptive refresh follows each account, network availability, power mode and screen lock. Server cooldowns always apply.
- Balance and budgets — Budget alerts at 80% and 100% of reported spend. Alerts only. Budgets do not block spending. Reported spend uses the provider’s time zone; API price estimates are excluded.
- MiniMax — Track MiniMax M Plan limits.

## 1.0.0

### Added

- Kazakh, Uzbek and Turkish across the app and widgets: thirteen languages. Uzbek copy uses Ö, Ğ, Ş and Ç as specified for this localization.
- Optional first-run setup with provider choices. Skip it or reopen it in Settings. Existing installations keep their preferences and do not show setup automatically; no provider reads begin until first-run setup is finished or skipped.
- Per-provider notification thresholds, independent reset alerts and quiet hours in this Mac’s time zone. Quiet alerts are skipped, not queued. Stale and expired readings do not trigger low-limit alerts.
- Optional CLI: usagenow status and usagenow status --json read the app’s safe snapshot, with freshness and reset times. No provider runtime, network, authentication or history export. Install from Settings › General; shell configuration is left to the user.
- Refresh after wake, notification migration and snapshot compatibility checks. CLI output clears percentages after reported resets, preserves unknown values and rejects unsupported snapshot versions.

- **Gemini 4 Argon cost estimates.** Official standard Gemini API prices: $2 input, $10 output (including thinking), and $0.10 cached input per million tokens through November 30, 2026; $4 / $20 / $0.20 from December 1. Estimates use each activity record's date, so past activity keeps its introductory rate. UsageNow uses midnight UTC for the published date change; these are estimates, not provider billing totals. The reviewed schedule is preserved when the bundled price table is regenerated.

## 0.9.0

### Added

- **JetBrains AI (experimental).** Local AI Assistant quota from a JetBrains IDE: monthly tariff remaining and a reported refill date, with menu-bar and widget support. A newer quota event from the same IDE can replace its XML cache; old readings keep their original time. No JetBrains credentials or network requests. Live validation with an active AI Assistant subscription is still pending.
- **Personal widgets.** Choose providers and accounts independently for each widget, or leave the selection empty to follow UsageNow. Renaming an account keeps the selection; a removed account never silently switches to another.
- **Large widget.** Up to four detailed provider/account rows, with two quota windows and their reset times. Like the smaller widgets, it only renders the sanitized snapshot.
- **Quota pace.** A local chart and a clearly labelled estimate for the most critical window, based on at least three fresh quota observations spanning 15 minutes. Cached repeats, stale readings, long gaps, resets and unknown window lengths do not produce a forecast. Estimates never use token counts.
- **Optional service incidents.** Public OpenAI, Claude, Cursor and GitHub Copilot status checks, off by default and cached for ten minutes. Service status is separate from account connections and usage limits; no usage or account data is sent.
- **Dutch (Nederlands).** App, widgets and bundled release notes, bringing UsageNow to ten languages.
- **Refreshed Windsurf and ElevenLabs icons.** Proper provider artwork with light and dark appearance support.

- **Antigravity without the IDE.** If the IDE cannot answer, read the official `agy /usage` report from compatible CLI 1.x versions (1.1.11 or later). No agent turn, no credential access by UsageNow; reports are cached for five minutes. Verified with CLI 1.2.2.

## 0.8.0

### Added

- **Check before saving a connection.** Manual keys, tokens, and session cookies are verified with the provider's existing read-only usage request before Keychain changes. The first-account and added-account sheets distinguish rejected credentials, missing permissions, offline services, unsupported responses, and Keychain failures. Canceling keeps the previous connection unchanged.
- **Respect provider request limits.** HTTP 429 pauses that connection until Retry-After allows another request (five minutes when absent or invalid). Background refresh, manual refresh, and connection checks share the pause; other accounts continue. Last known values keep their original reading time.
- **Cursor, GitHub Copilot, Perplexity, ElevenLabs, and Z.ai connections.** Explicitly connected, off by default, with separate accounts and menu-bar/widget integration. Cursor, Copilot, Perplexity, and Z.ai use experimental endpoints. ElevenLabs uses the official subscription API with `user_read` permission. Availability depends on the plan and credential; not every plan or token type has been verified.
- **Optional isolated web sign-in for Cursor and Perplexity**, plus a manual named session cookie fallback. No existing browser profile is imported. Selected cookies, user-supplied GitHub tokens, and API keys are stored only in UsageNow's Keychain and sent only to their service's host.
- **Absolute credit and character counters**, kept separate from daily local activity. Unlimited or unreported allowances never become an invented percentage.
- **Windsurf.** Daily and weekly limits, reset times, and the plan Windsurf cached on this Mac. Older plans can show billing-cycle prompt credits and flow actions instead. UsageNow reads only the cached plan, never Windsurf's sign-in, and makes no network request. Windsurf must run to refresh its cache; token activity isn't available through this integration. Available fields depend on the plan and Windsurf version.
- **Portuguese, Japanese, Korean, and Hebrew**, bringing UsageNow to nine languages. The widget follows the chosen language, including right-to-left layout for Hebrew.
- **What's New in your language.** Release notes are bundled in every supported language and work offline; a missing translation falls back to English.
- **Choose an added account for the menu bar**, such as “Codex · Work”. The choice is remembered; removing the account falls back to the provider's first account.

### Fixed

- **Widget freshness belongs to each provider.** Updating one provider no longer makes another provider's old quota look newly read. A clock marks stale readings.
- **Widget limits expire at their reset time**, including while the app is closed. An expired percentage becomes unknown until new data arrives; it never turns into an invented 100% remaining.
- **Widget countdowns keep ticking** between extension refreshes. Timelines also include upcoming resets and the point when a reading becomes stale.
- **A fresh reading of unchanged limits is saved**, so the shared snapshot doesn't keep an old date merely because the percentage stayed the same.

### Development

- Debug builds use separate app and widget identifiers, preferences, and an App Group. They cannot replace the installed widget's registration or overwrite its snapshot. Automatic updates are disabled in Debug builds, and unit tests don't start live providers.

## 0.7.2

### Fixed

- **Privacy and About couldn't be opened in Russian, French, or Spanish.** Their tab titles didn't fit the Settings window, so macOS moved the last tabs into an overflow menu where they couldn't be chosen. The window now widens to fit every tab's title in the language UsageNow runs in.

## 0.7.1

### Added

- **Choose UsageNow's language** in **Settings › General › Language**: follow macOS, or pick German, English, Spanish, French, or Russian, then **Restart Now**. The widget follows too. It's the same setting as **System Settings › General › Language & Region › Applications**, so the two always agree.
- **Rename an added account** from its **…** menu in **Settings › Providers**.

### Changed

- **An added account's actions share one menu**, so its row fits in every language.
- **An empty or missing account folder says so.** The menu bar window says the folder has no sign-in or sessions, rather than asking you to sign in, and Settings marks a folder that was moved or deleted.
- **Report a Problem includes the language** UsageNow is set to and running in.

### Fixed

- **Adding an account made the other added accounts read their month of sessions again.** Accounts that didn't change keep what they've read.

## 0.7.0

### Added

- **More than one account.** Under Codex, Claude Code, DeepSeek, Kimi, OpenRouter, and Ollama Cloud in **Settings › Providers**, **Add Account…** adds another: the folder `CODEX_HOME` or `CLAUDE_CONFIG_DIR` points to, or another API key, kept like the first. Each account gets its own section, widget row, and notifications under a name you choose, such as "Codex · Work". UsageNow never reads an account's own name or email. An added Claude Code account shows only the limits Claude Code records reaching.
- **Qwen Code.** Today's tokens, answers, and models, and what they would have cost, from the session recordings Qwen Code writes on your Mac. Only each answer's identifier, time, model, and token counts are decoded — never the messages — and Qwen Code's sign-in is never opened. Not yet verified against a live install.
- **Cline.** Today's tokens, API requests, and models, with the cost Cline recorded for them, from the tasks the extension saves in VS Code, Cursor, Windsurf, Kiro, VSCodium, or Trae, and the sessions the Cline CLI saves. Only the numbers, the model, and the time are read; prompts, replies, and Cline's keys never are.
- **Grok Build.** Today's tokens, model calls, and models, with the cost xAI reported, from the session logs Grok Build writes on your Mac. Only finished turns' numbers, models, and times are decoded. Not yet verified against a live install.
- **The last two weeks in the widget.** A provider without limits to show — Gemini CLI, Warp, OpenCode, Qoder, and the three new ones — gets a small chart of its last 14 days in the medium widget's rows, today's bar highlighted. The widget receives only the shape — each day as a share of the busiest — never amounts. It follows **Settings › General › Show the last 30 days**.
- **UsageNow in German, Spanish, French, and Russian.** The app and the widget follow your Mac's language; choose another for UsageNow alone in **System Settings › General › Language & Region › Applications**. Counts use each language's plural forms, and the widget uses short units so longer words still fit.
- **What's New** in **Settings › About**: every version's changes, newest first, with the installed one marked. The list ships inside the app, so it opens offline and matches your version.

### Changed

- **Cost for Cline and Grok Build is the tool's own.** Both record what each request cost at the prices of the provider you ran them with; UsageNow shows that figure, and estimates only a request they recorded no cost for.
- **Cursor and GitHub Copilot** are what's left under **Coming soon**.

## 0.6.1

### Added

- **Notifications about limits.** Turn them on in **Settings › Notifications**, and UsageNow tells you when a limit is down to 20% and again at 5% — once each, not on every refresh — and when a limit it warned you about has reset, so you know you can go on. The reset notice is scheduled with macOS when the warning goes out, so it arrives on time even if UsageNow isn't running. A limit you were never warned about resets silently. The wording follows **Show limits as**. Off by default; notifications come from this Mac, and nothing is sent anywhere.
- **A keyboard shortcut to open UsageNow** from any app. Record your own in **Settings › Menu Bar**; there's no default, because every combination is already taken in somebody's setup. Press it again, press Escape, or click elsewhere to close. It needs no Accessibility or Input Monitoring permission: macOS tells UsageNow only that its own shortcut was pressed.

### Changed

- **The cost estimate knows Claude Sonnet 5.5 and GPT-6.1.**

### Fixed

- **"Try Again", a newly added API key, or a provider just turned on could be ignored** when pressed while a refresh was already running: the request waited for that refresh and then did nothing. It now runs as soon as the refresh ends.
- **Antigravity no longer holds up other providers.** Finding its language server runs two system tools, and waiting for them blocked a thread the other providers' refreshes share.
- **A very long line in a session file is skipped without being loaded.** A pasted image or a huge tool result could cost its whole size in memory just to be passed over. Lines over 16 MB — larger than any usage record — are now skipped as they're read.

## 0.6.0

### Added

- **The last 30 days.** Under each provider, a bar per day with the month's totals beneath: tokens, what they would have cost at API prices, and the model used most. Hover a bar to see that day. Tools that meter in credits chart credits (Kiro, Qoder), and Warp charts requests, the only thing it times per request. Days are your calendar's days, so a day with a clock change is still one bar. Turn the charts off in **Settings › General** to keep the window short.
- **OpenCode.** Today's tokens, requests, and models, and what they would have cost, from OpenCode's local database, opened read-only. SQLite hands over only each answer's time, model, and token counts — reply text stored beside them never leaves the database. Not yet verified against a live OpenCode install.
- **Qoder.** Credits spent today and the answers they paid for, from the transcripts Qoder's agent writes on your Mac — the amount Qoder charged, after any discount. Qoder records no tokens and names models by internal aliases, so neither is shown, and its plan's remaining credits live only in its app, so no limit is shown. Qoder's sign-in is never opened.
- **Ollama Cloud (experimental).** Session and weekly limits for your account, with your own Cloud API key, kept like the other keys: only in your Keychain and sent only to `ollama.com`. Ollama doesn't document this, so it may stop working without notice; a changed answer shows the limits as unavailable rather than a guess. Ollama gives no reset time, so none is shown. Not yet verified against a live account.
- **Remaining or used.** **Settings › General › Show limits as** switches every percentage — popover, menu bar, and widget — between what's left and what's used. With "Used", bars grow instead of shrinking.
- **Credits in the widget** for Kiro, Warp, and Qoder, where there are no limits to show.
- **Report a Problem** in **Settings › About**. It shows the whole report first — versions, screen sizes, settings, and what each provider shows — and sends nothing itself: it opens a prefilled GitHub issue or email. Names, emails, file paths, keys, and prompts are never in it.

### Changed

- **The menu bar window is more opaque**, so dark windows behind it no longer make light-mode text hard to read.
- **The menu bar window never runs off the screen.** When the providers are taller than the screen, the list scrolls.
- **Settings › Providers fits a laptop screen.** The list scrolls, and the providers still to come share one row.
- **The cost estimate knows the newest models**, including Claude Opus 5.5 and GPT-6, and models OpenCode users often run: DeepSeek, Kimi, Grok, and Devstral. A retired model keeps its last price, so older sessions stay priced. Older Codex sessions are now priced too.
- **Reading a month of session files is several times faster**: the first read of 1.3 GB went from 13 seconds to under 1.5.
- **Today's numbers stay on one line** when the cost estimate is shown.
- **Warp and OpenCode are read only when they changed.** Their databases are read again when the database or its write-ahead log changes, or a new day begins — not on every refresh.

### Fixed

- **Codex limits stopped updating with ChatGPT 26.9**, which moved its bundled Codex CLI. UsageNow now finds it there, and also finds the CLI bundled with the Codex extension for VS Code, Cursor, Windsurf, Kiro, and Qoder. Until now, Codex showed the limits last written to a session file — sometimes days old.
- **Stale Claude limits now say how to refresh them.** When Claude Code's sign-in has expired, the last known limits stay on screen with how old they are, and now with "Refresh Claude Code from Terminal" beside them, so an hour-old percentage isn't read as current.
- **The widget reads data from a newer version of the app**, skipping a provider it doesn't know instead of asking you to open UsageNow.
- **Memory while reading session files.** Every chunk of a file stayed in memory until the whole file was read, so the first read of a month of sessions could peak at 1.4 GB. It now stays under 500 MB, usually around 200 MB, and the memory is handed back to the system once the read is done.
- **UsageNow could quit without a word** if the Codex app-server exited before UsageNow finished talking to it. That's now a failed refresh, like any other.
- **A database that couldn't be opened** — Warp's when macOS denies access, or a damaged OpenCode file — was closed twice. It's now closed once.
- **A data race** when several providers connected with API keys refreshed at the same moment for the first time.

## 0.5.0

### Added

- **Kiro.** A new provider with your plan's monthly credit limit, when it resets, and today's credits and prompts. Kiro offers no public way to read its limits, but it writes the answer it receives to its own log; UsageNow reads that, and makes no request of its own. The account identifiers in the same answer are never read. A free trial that has ended is ignored, so a plan with every credit left isn't shown as exhausted. While Kiro is closed, the last limits it recorded stay on screen with when they were read.
- **Warp.** A new provider with today's agent requests, credits, and tokens per model, read from Warp's local database, opened read-only. The text of prompts and replies is never read. Warp keeps one running credit total per conversation, so a conversation that began before today is left out and today's credits are marked partial rather than overstated. No usage limit is shown: the one in Warp's settings still describes its earlier request-based plans.
- **DeepSeek, Kimi, and OpenRouter, with your own API key.** Each shows what its official API reports: DeepSeek's balance in your account's currency, Kimi's available balance, and OpenRouter's spending today and this month, with the key's limit as a window when it resets. Add a key in **Settings › Providers**. The key is kept only in this Mac's Keychain, sent over HTTPS only to that provider's host, and deleted when you turn the provider off. Redirects aren't followed and answers from other hosts are refused, so the key can't be passed on. These providers start off. All three follow their documented responses but are not yet verified against live accounts.
- **Credits today** for tools that meter in credits, and a **Monthly** limit window.

## 0.4.0

### Added

- **What today's tokens would cost.** Each provider shows an estimate beside its token and request counts — "≈ $4.20 at API prices" — of what the day's activity would have cost had it been billed through the API. Your subscription doesn't charge per token, so this is a sense of scale, not a bill. Cached tokens are priced as cached: on Claude Code most of the volume is cache reads at a tenth of the input price, so counting everything at the input rate would overstate a day sevenfold. A model with no published price isn't counted at all, and the line says the estimate is partial instead of quietly leaving it out. Prices ship with the app and are refreshed each release.
- **Updates in the app.** UsageNow can now check for updates and install them. **Settings › General** has the switch and a Check Now button. An update is installed only when it carries UsageNow's signature, and checking sends nothing about you — no identifier and no system profile. A build that wasn't made by the release process, such as one you build yourself, can't update itself at all. Coming from 0.3.0, install this version by hand once; later versions arrive on their own.

### Changed

- **Refresh shows progress instead of spinning.** The button is an arrow at the weight of the settings gear beside it, and while a refresh runs an arc sweeps around it.
- **The menu bar percentage is sized to the icons around it**, rather than to the menu bar's own larger text, so it no longer stands out from its neighbours.

## 0.3.0

### Added

- **Gemini CLI.** A new provider, with the same enable, refresh, menu bar, widget, and telemetry behavior as Codex and Claude Code. Activity and models come from Gemini CLI's local session recordings. Gemini CLI records no usage limits locally, so none are shown. Credential files are never opened.
- **Antigravity.** A new provider with usage limits, and the same enable, refresh, menu bar, and widget behavior. Limits from the Antigravity app itself: while it runs, UsageNow reads the loopback port and CSRF token the app prints in its command line, then asks its language server for the quota summary its `/usage` panel shows — 5-hour and weekly windows per model group, plus the plan. No credentials are read or sent, and nothing leaves `127.0.0.1`. Between runs the last limits stay for a day, marked stale. (The Antigravity CLI's own server can't be read, so the app must be running.)
- **Activity by model.** A compact **Models today** list in each provider's section shows tokens and requests per model, most active first. It works for any model identifier, including ones released later, and never shows a percentage: account limits aren't split by model. Available for Claude Code, Codex, and Gemini CLI.
- **Team plans.** Claude Team and Enterprise show the member's seat, such as **Team · Premium**. Codex reads the plan from `account/read`, so Team, Business, and Enterprise accounts show their plan even when rate limits aren't returned, and newer billing variants map to their plan name. Not yet verified against live Team accounts.
- **Gemini CLI usage** and **Antigravity usage** menu bar modes. Gemini CLI's shows the icon while it reports no limits.
- **Reorder providers.** Drag providers in Settings › Providers, or use Move Up and Move Down; the popover and widget follow that order.
- **Cursor** and **GitHub Copilot** are listed as Coming soon.

### Changed

- The medium widget shows one row per provider when three or more are on; the small widget lists up to three. When not everything fits, providers closest to a limit win. Windows of the same length from one provider carry their scope, such as "Weekly · Opus".
- A provider added in an update starts on once, as it would for a new user. Providers you turned off stay off.

### Fixed

- **No more login-password prompts for Claude limits.** Claude Code saves its sign-in with macOS’s `security` tool, and every save resets which apps may read it, so 0.2.0 asked for the login password after each renewal, even after **Always Allow**. UsageNow now reads the sign-in the way Claude Code does, with `/usr/bin/security`. Turning on the setting is the consent; the token is still kept only in memory.
- **Claude limits come back by themselves after Claude Code renews its sign-in.** 0.2.0 stopped reading the keychain after an expired sign-in until you chose **Try Again**, so a sign-in renewed by running `claude` went unnoticed. UsageNow now watches when the keychain item last changed — reading no secret and showing no prompt — and reads the new sign-in on the next refresh.
- **Last known Claude limits survive quitting and updating the app.** They were kept in memory only, so installing an update overnight left an empty panel in the morning. Percentages and reset times — never credentials — are now stored locally for up to a day, and removed when the setting is turned off.
- **A Claude window that reset after the last reading stays on screen.** It used to disappear, so an old reading showed only the weekly limit. It now shows as "5-hour —" with "Reset Mon 22:59 · not updated since", and the way to refresh stays visible.
- **Claude limits you hit show up without a sign-in.** When Claude Code stops a request at a limit, it records which window and when it resets; UsageNow reads that from the transcript and shows the window as used up until then — also when the experimental source is off, or when you work in the Claude app, whose sign-in UsageNow can't use.
- **UsageNow no longer runs `claude auth status` when the Claude sign-in expires.** 0.2.0 did, expecting the CLI to renew its sign-in; on current versions it exits successfully without renewing, so it only started a process for nothing.

## 0.2.0

### Added

- **Real provider data.** Codex usage limits, reset times, and plan come from the official `codex app-server`, with the latest limits recorded in local sessions as a stale fallback. Token, request, and model activity for both Codex and Claude Code comes from local session files.
- **Desktop widget.** Small and medium WidgetKit widgets. The small size shows each provider's tightest window plus the next reset; the medium size gives each provider a column of windows. The widget renders a sanitized snapshot the app publishes to an App Group — it never touches providers, files, the keychain, or the network.
- **Providers settings.** Codex and Claude Code can be tracked independently, both on by default. A disabled provider is never refreshed or read from disk. Gemini CLI, DeepSeek, and Qwen are listed as roadmap entries.
- **Claude usage limits (experimental, off by default).** Reads the existing Claude Code sign-in from the keychain and asks Anthropic's usage endpoint. When the saved sign-in has expired, UsageNow asks the Claude Code CLI to renew it and reads the keychain again; it never refreshes, rotates, or writes credentials itself.
- **Appearance setting** — Light, Dark, or System — with Light as the default.
- **Menu bar display modes:** icon only, most critical usage, or a specific provider.
- **Telemetry foundation:** anonymous installation identity, a small event set, and a network client. Off by default, and no endpoint is configured yet, so nothing is sent.
- **Localization readiness** through a String Catalog, with numbers formatted to match the UI language.

### Changed

- Usage is shown as what's left ("58% left"), and bars shrink as usage grows.
- Quota windows are whatever a provider reports — an account may have only a weekly window — and a missing window is never invented.
- When quota can't be fetched, UsageNow says why in one line instead of a blanket message.
- A quota that can't be read right now — an expired sign-in, a denied keychain, an endpoint that didn't answer — no longer blanks the display. The last known limits stay for a day, shown as stale, so an overnight expiry doesn't leave an empty menu bar in the morning. Only an account that genuinely has no limits clears them.

## 0.1.0

- First milestone: native menu bar app with mock providers, settings, states, and tests.
