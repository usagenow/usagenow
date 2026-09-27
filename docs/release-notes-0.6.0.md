# UsageNow 0.6.0

AI coding usage tracker for macOS. Usage, limits, reset times, and activity across Codex, Claude Code, Gemini CLI, Antigravity, Kiro, Warp, OpenCode, and Qoder — plus DeepSeek, Kimi, OpenRouter, and Ollama Cloud — from the menu bar.

## New

- **The last 30 days** — under each provider, a bar per day, with the month's tokens, what they would have cost at API prices, and the model you used most. Hover a bar to see that day. Kiro and Qoder chart credits, Warp charts requests. Turn the charts off in Settings › General.
- **OpenCode** — today's tokens, requests, and models, and what they would have cost, from OpenCode's local database, read-only. Only the numbers are read; prompts and replies never are.
- **Qoder** — credits spent today and the answers they paid for, from the transcripts Qoder writes on your Mac. Qoder's sign-in is never opened.
- **Ollama Cloud** (experimental) — your session and weekly limits, with your own Cloud API key. Ollama doesn't document this, so it may stop working without notice; if it does, the limits show as unavailable rather than wrong.
- **Remaining or used** — Settings › General › Show limits as switches the popover, menu bar, and widget between what's left and what's used.
- **Credits in the widget** for Kiro, Warp, and Qoder.
- **Report a Problem** — Settings › About shows the whole report first and opens a prefilled GitHub issue or email. No names, emails, paths, keys, or prompts.

## Improved

- The menu bar window is more opaque, and scrolls instead of running off a small screen.
- Settings › Providers fits a laptop screen.
- The cost estimate knows the newest models, including Claude Opus 5.5 and GPT-6, and DeepSeek, Kimi, Grok, and Devstral. Older Codex sessions are priced too.
- Reading a month of session files is several times faster, and takes far less memory: the first read peaked at 1.4 GB and now stays under 500 MB, usually around 200 MB.

## Fixed

- Codex limits stopped updating with ChatGPT 26.9, which moved its bundled Codex CLI. UsageNow finds it again, and also finds the one bundled with the Codex extension for VS Code, Cursor, Windsurf, Kiro, and Qoder.
- Stale Claude limits now say "Refresh Claude Code from Terminal" beside them, so an hour-old percentage isn't read as current.
- The widget reads data from a newer version of the app instead of asking you to open UsageNow.
- UsageNow could quit without a word if the Codex app-server exited early.
- A database that couldn't be opened was closed twice.
- A data race when several API-key providers first refreshed at once.

OpenCode and Ollama Cloud follow their documented or observed formats but aren't yet verified against live accounts. If something looks wrong, Settings › About › Report a Problem.

## Install

Already on 0.4.0 or later? UsageNow offers this update itself — or choose **Check Now** in Settings › General.

Otherwise, download `UsageNow-0.6.0.dmg` below and drag UsageNow to Applications.

Requires macOS 15 or later. Signed with a Developer ID and notarized by Apple.
