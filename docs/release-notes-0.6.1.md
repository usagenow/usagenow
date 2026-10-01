# UsageNow 0.6.1

AI coding usage tracker for macOS. Usage, limits, reset times, and activity across Codex, Claude Code, Gemini CLI, Antigravity, Kiro, Warp, OpenCode, and Qoder — plus DeepSeek, Kimi, OpenRouter, and Ollama Cloud — from the menu bar.

## New

- **Notifications about limits** — turn them on in Settings › Notifications. UsageNow tells you when a limit is down to 20% and again at 5%, once each, and when a limit it warned you about has reset. Off by default; they come from this Mac, and nothing is sent anywhere.
- **A keyboard shortcut to open UsageNow** from any app — record your own in Settings › Menu Bar. No Accessibility or Input Monitoring permission needed.

## Improved

- The cost estimate knows Claude Sonnet 5.5 and GPT-6.1.

## Fixed

- "Try Again", a newly added API key, or a provider just turned on could be ignored when pressed while a refresh was running.
- Antigravity no longer holds up other providers while UsageNow looks for its language server.
- A very long line in a session file — a pasted image, a huge tool result — is skipped without being loaded into memory.

## Install

Already on 0.4.0 or later? UsageNow offers this update itself — or choose **Check Now** in Settings › General.

Otherwise, download `UsageNow-0.6.1.dmg` below and drag UsageNow to Applications.

Requires macOS 15 or later. Signed with a Developer ID and notarized by Apple.
