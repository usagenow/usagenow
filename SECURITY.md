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

- Usage data stays on your Mac. Nothing from `~/.codex`, `~/.claude`, or `~/.gemini` is sent to UsageNow servers.
- UsageNow never reads Codex credentials; the official Codex app-server authenticates itself.
- **UsageNow never modifies or stores your Claude Code credentials, and never uses your refresh token.** The experimental Claude usage limits feature (off by default) reads the existing sign-in from the keychain only after you enable it, with `/usr/bin/security find-generic-password` — the same tool Claude Code uses to save and read it. Enabling the setting is the consent; macOS shows no prompt. Only the access token and its expiry are kept, in memory; the token is sent only to `api.anthropic.com` and is never logged or written anywhere.
- While the saved sign-in is expired, UsageNow checks only when the keychain item last changed, which reads no secret. It never runs Claude Code and never renews the credential itself.
- UsageNow never opens Gemini CLI credential files and never reads or stores Gemini CLI tokens. From `~/.gemini` it reads only the configured sign-in method, whether a saved sign-in exists, and session recordings.
- **UsageNow never refreshes, modifies, or stores the Google sign-in Antigravity CLI saved, and never uses its refresh token.** The experimental Antigravity usage limits feature (off by default) reads that sign-in only after you enable it, with `/usr/bin/security find-generic-password`, the tool `agy` saves it with; enabling the setting is the consent. Only the access token and its expiry are kept, in memory; the token is sent only to Google's Cloud Code host and is never logged or written anywhere.
- Session files are read for timestamps, identifiers, model names, and token counts only. Prompts, responses, tool inputs, and code are never stored or logged.
- Optional analytics are off by default and never include prompts, conversation or session contents, source code, project names, file paths, credentials, token or request values, quotas, reset times, models or per-model activity, plans, or Team status.

Issues that break these guarantees are in scope.
