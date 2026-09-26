# Security Policy

## Reporting a vulnerability

Please don’t open a public issue for security problems.

Report vulnerabilities privately through GitHub’s [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) on the UsageNow repository. Include:

- a description of the issue and its impact
- steps to reproduce
- the UsageNow and macOS versions you tested

We’ll acknowledge your report as soon as we can and keep you updated while we work on a fix.

## Supported versions

UsageNow is in early development. Only the latest release receives security fixes.

## Scope and principles

UsageNow is local-first:

- Usage data stays on your Mac. Nothing UsageNow reads from other tools — `~/.codex`, `~/.claude`, `~/.gemini`, `~/.kiro`, `~/.qoder`, Kiro's logs, or the Warp and OpenCode databases — is sent to UsageNow servers.
- UsageNow never reads Codex credentials; the official Codex app-server authenticates itself.
- **UsageNow never modifies or stores your Claude Code credentials, and never uses your refresh token.** The experimental Claude usage limits feature (off by default) reads the existing sign-in from the keychain only after you enable it, with `/usr/bin/security find-generic-password` — the same tool Claude Code uses to save and read it. Enabling the setting is the consent; macOS shows no prompt. Only the access token and its expiry are kept, in memory; the token is sent only to `api.anthropic.com` and is never logged or written anywhere.
- While the saved sign-in is expired, UsageNow checks only when the keychain item last changed, which reads no secret. It never runs Claude Code and never renews the credential itself.
- UsageNow never opens Gemini CLI credential files, never reads or stores Gemini tokens, and never contacts Google. From `~/.gemini` it reads only the configured sign-in method, whether a saved sign-in exists, and session recordings.
- For Antigravity, UsageNow asks the Antigravity app's own language server on `127.0.0.1` while the app runs. It reads only the port and CSRF token the app prints in its own command line (via `ps`), finds the socket with `lsof`, reads no other process's arguments or memory and never the Google sign-in Antigravity saved, and sends no other credentials. Certificate checks are skipped for loopback addresses only.
- For Kiro, UsageNow reads the usage answer Kiro writes to its own log (`~/Library/Application Support/Kiro/logs`) for the plan, credit amounts, and reset date, and the credits recorded in `~/.kiro/sessions`. It sends no request to Kiro, reads no Kiro sign-in, and never reads the account identifiers in the same log lines.
- Warp's database is opened read-only. Only request times and outcomes, per-conversation credit totals, and tokens per model are selected; the text of prompts and replies is never read, and no Warp credential is read.
- OpenCode's database (`~/.local/share/opencode`) is opened read-only. SQLite extracts only the time, model, and token counts of each answer; the rest of the message, including reply text stored beside them, never leaves the database, and prompt tables aren't read. OpenCode's sign-in file is never opened.
- For Qoder, UsageNow reads the transcripts in `~/.qoder/projects` for each answer's time, request identifier, and credits. Prompts, replies, and tool results on the same lines are never decoded, and Qoder's sign-in (`~/.qoder/.auth` and the app's own auth files) is never opened.
- Session files are read for timestamps, identifiers, model names, and token or credit counts only. Prompts, responses, tool inputs, and code are never stored or logged.
- **API keys you add** (DeepSeek, Kimi, OpenRouter, and the experimental Ollama Cloud) are stored only in this Mac's Keychain and not synced. Each key is sent over HTTPS only to its provider's own host — `api.deepseek.com`, `api.moonshot.ai`, `openrouter.ai`, or `ollama.com` — and only to read balance, spending, or limits. Redirects are never followed and answers from any other host are refused, so a key can't be passed on. Keys are never logged or written anywhere else, and are deleted when you turn the provider off. These services don't offer read-only keys, which is why UsageNow suggests creating a separate one.
- Ollama Cloud's usage endpoint isn't documented by Ollama. It's labeled Experimental, and a changed answer shows limits as unavailable rather than a guessed number.
- Updates are installed only when signed with UsageNow's update key (Sparkle, EdDSA). Checking for updates sends no identifier and no system profile.
- **Report a Problem** (Settings › About) shows the whole report before anything leaves the Mac, and sends nothing itself: it opens your browser or mail app with the text filled in. The report holds versions, screen sizes, settings, and each provider's status and limits. Account names and emails, file paths, keys, tokens, and prompts are never in it, and error messages are cleaned of paths, emails, and key-shaped strings before they're included.
- Optional analytics are off by default and never include prompts, conversation or session contents, source code, project names, file paths, credentials, token or request values, quotas, reset times, models or per-model activity, plans, or Team status.

Issues that break these guarantees are in scope.
