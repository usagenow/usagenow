# Explicit provider connections (0.8.0)

All five are off by default. Enabling a provider without a saved credential
does not send a request. Connecting does not buy, generate, or spend anything.
It only reads usage. Availability depends on the account, plan, and endpoint;
not every paid plan or token type has been verified.

| Provider | Credential and read endpoint | Limitations |
|---|---|---|
| Cursor | Web session; `GET https://cursor.com/api/usage-summary` | Experimental. Only personal allowance: shared team pools are not read or substituted. Auto/API component percentages are not averaged. No token activity or cost estimate. |
| GitHub Copilot | User-supplied GitHub token; `GET https://api.github.com/copilot_internal/user` | Experimental. No VS Code OAuth client ID or impersonating headers. Token compatibility is not guaranteed. Unlimited and zero/zero placeholders have no percentage. Real credit counters are retained without summing duplicate pools. |
| Perplexity | Web session; `GET https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default` | Experimental; not the Sonar API. Reports credits, not dollars. Mixed grant balances only get a percentage if grants reconcile with usage and balance. No inferred plan or spending order. Renewal only applies to a recurring-only pool. |
| ElevenLabs | Restricted API key with `user_read`; `GET https://api.elevenlabs.io/v1/user/subscription` | Official API. Monthly character count and limit; only an explicit reset date. Missing key permission is distinguished from rejected credentials. No audio generation. |
| Z.ai | Personal API key; `GET https://api.z.ai/api/monitor/usage/quota/limit` | Experimental global Coding Plan endpoint. No zhipuai.cn/China or organization admin integration. Windows come from reported units; implausible five-hour reset timestamps are omitted. |

## Sign in and storage

Cursor and Perplexity offer **Sign In** in the connection sheet. It creates a
new `WKWebView` with a nonpersistent website data store, starting on the official
dashboard. The current host is visible. Passwords are entered into the website,
not a UsageNow form. No JavaScript is injected to read passwords or tokens.
Only HTTPS navigation is allowed; TLS validation and the browser identity are
not overridden. Existing Safari/Chrome profiles are never read.

After sign-in, **Connect** selects secure, unexpired session cookies applicable
to the provider's usage endpoint, verifies them with a read-only request, and
returns them to the connection sheet. **Check and Save** or **Check and Add Account**
verifies the credential with the same read-only provider request before persisting
it. Manual credentials take this path too. Invalid credentials, missing permissions,
offline services, unrecognized responses, and Keychain failures have distinct safe
messages. Canceling before saving leaves Keychain unchanged, even if a late
verification response arrives. Embedded SSO can
be rejected by the identity provider: cancel and supply a named session cookie
manually instead. A system-browser login cannot safely hand its cookies back
without a provider-supported OAuth callback, so UsageNow does not claim to
support that flow.

Only allowlisted session cookie names (including contiguous numbered chunks)
are retained. Analytics cookies, emails and other cookies from a pasted header
are discarded before storage. Headers containing controls or ambiguous chunks
are rejected. Credentials live only in the app's device-local Keychain entries
and transient process memory. They are not copied into UserDefaults, telemetry,
logs, widgets, or source fixtures. Explicit connections may contain powerful
credentials; use restricted, dedicated keys where possible.

Usage requests go over HTTPS to the single catalog host; the shared transport
refuses every redirect and uses no shared cookie jar. Turning a provider off
deletes its credentials; removing an extra account deletes its credential.
Replacing a credential clears prior account readings and ignores their in-flight
responses. Network failures keep the last reading with its original date.
No provider login is launched automatically at app startup, no Claude/Codex
credential behavior changes, and no background credential renewal is added.

HTTP 429 pauses further requests for that credential at that host. Refresh and
connection verification share the pause, including manually requested retries.
Retry-After accepts integer seconds or an HTTP date; a missing or invalid value
uses five minutes. Other accounts are unaffected. The cooldown holds only an
ephemeral keyed fingerprint and a deadline in memory, never the credential, and
neither is persisted or sent to telemetry or the widget. Existing readings retain
their original timestamps. No response body or raw server error is displayed.

## Sources and attribution

Schema research used [CodexBar](https://github.com/steipete/CodexBar) at commit
[`6e118bdb5782707bfb0dfd0453d3483e3b216cd0`](https://github.com/steipete/CodexBar/tree/6e118bdb5782707bfb0dfd0453d3483e3b216cd0):
`docs/{cursor,copilot,perplexity,elevenlabs,zai}.md`, the Cursor usage summary
decoder, `CopilotUsageModels.swift`, and the Perplexity/Z.ai/ElevenLabs plugins.
These integrations were implemented using UsageNow's existing provider,
Keychain, transport, and sanitized snapshot abstractions. CodexBar's browser
cookie importer and VS Code OAuth identity are **not** included. The MIT notice
is included in Settings › About › Open Source Licenses and below.

Official references:

- [ElevenLabs subscription API](https://elevenlabs.io/docs/api-reference/user/subscription/get)
- [GitHub billing usage API](https://docs.github.com/en/rest/billing/usage) — distinct from the experimental Copilot endpoint.

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
