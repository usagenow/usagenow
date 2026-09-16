# UsageNow telemetry receiver

A Cloudflare Worker that receives UsageNow's anonymous, opt-in analytics and
stores them in D1. It is published here because the app promises what the
analytics can contain — this is the other half of that promise, and it can be
read alongside `UsageNow/Telemetry` in the app.

Analytics are off by default in every build, and a build made without a
telemetry endpoint sends nothing at all.

## What it accepts

`POST /v1/events` takes exactly one JSON body — the seven fields of the app's
`TelemetryPayload` and nothing else:

```json
{
  "event": "app_active",
  "installation_id": "3f2a1b7c-5d4e-4f8a-9b0c-1d2e3f4a5b6c",
  "app_version": "0.3.0",
  "build": "1",
  "macos_version": "15.6.1",
  "architecture": "arm64",
  "timestamp": "2026-09-16T11:59:30Z"
}
```

A body with an unknown event, a malformed field, or any extra key is refused
with `400` and never stored, so provider data cannot end up in the table even
if some future client sent it by mistake. Everything else answers `204`: a
duplicate, a capped installation and a stored row look the same from outside.

What the Worker adds is the two-letter country Cloudflare resolved for the
connection, and its own receive time. IP addresses, headers and user agents are
never written to the database or the logs.

Limits: bodies over 2 KB are refused, at most 200 rows per installation per UTC
day, and a unique index on installation, event and timestamp makes a retry
idempotent. A daily cron deletes rows older than `RETENTION_DAYS` (180).

## Looking at the numbers

`GET /` is a one-page dashboard, and `GET /v1/stats?days=30` is the same data as
JSON. Both need `Authorization: Bearer $STATS_TOKEN`. Every figure is a count of
installations or events; there is no endpoint that returns a row about one
installation.

## Deploy

Run these from this directory. `wrangler login` opens a browser for Cloudflare;
nothing here needs your Apple credentials.

```bash
npm install
```

```bash
npx wrangler login
```

```bash
npx wrangler d1 create usagenow-telemetry
```

Copy the `database_id` it prints into `wrangler.toml`, then create the table:

```bash
npx wrangler d1 execute usagenow-telemetry --remote --file=./schema.sql
```

Generate a dashboard token and store it as a secret — it is never written to a
file in this repository:

```bash
openssl rand -base64 32
```

```bash
npx wrangler secret put STATS_TOKEN
```

```bash
npx wrangler deploy
```

`wrangler.toml` claims `telemetry.usagenow.com` as a custom domain, so the
usagenow.com zone must be in the same Cloudflare account. Cloudflare issues the
certificate; there is no workers.dev URL.

Check it end to end:

```bash
curl -si -X POST https://telemetry.usagenow.com/v1/events -H 'content-type: application/json' -d '{"event":"app_active","installation_id":"3f2a1b7c-5d4e-4f8a-9b0c-1d2e3f4a5b6c","app_version":"0.3.0","build":"1","macos_version":"15.6.1","architecture":"arm64","timestamp":"2026-01-01T00:00:00Z"}' | head -1
```

That timestamp is deliberately old, so the receiver should answer `400` and
store nothing. Repeat with a current timestamp to see `204`, then open
<https://telemetry.usagenow.com/> and paste the token.

## Point a build at it

Nothing reaches this Worker until an app build is made with the endpoint. The
released 0.3.0 has none, so it sends nothing whatever a user chooses.

```bash
USAGENOW_TELEMETRY_ENDPOINT=https://telemetry.usagenow.com/v1/events scripts/build-release.sh
```

A debug build can be pointed at a local receiver without rebuilding, with
`-UsageNowTelemetryEndpoint http://localhost:8787/v1/events` as a launch
argument.

## Develop

```bash
npm test
```

```bash
npm run check
```

`npm run dev` starts the Worker locally against a local D1. Copy
`.dev.vars.example` to `.dev.vars` for a dashboard token, and apply the schema
once with `npx wrangler d1 execute usagenow-telemetry --local --file=./schema.sql`.
