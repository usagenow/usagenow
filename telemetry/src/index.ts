/**
 * The UsageNow telemetry receiver.
 *
 * It accepts the single event body the app sends, stores it in D1, and
 * serves aggregates behind a token. It deliberately has no other surface:
 * no read API for a single installation, no way to delete or amend a row
 * from outside, and no logging of IP addresses, headers or user agents.
 *
 * Released builds send nothing until they are built with
 * USAGENOW_TELEMETRY_ENDPOINT pointing here, and every user starts opted out.
 */

import { collectStats } from "./stats";
import { country, parseEvent, utcDay } from "./validate";

export interface Env {
  DB: D1Database;
  /** Bearer token for the dashboard and /v1/stats. Set with `wrangler secret put`. */
  STATS_TOKEN?: string;
  /** How long rows are kept. Defaults to 180 days. */
  RETENTION_DAYS?: string;
}

/** Bodies larger than this are refused unread: the real one is ~250 bytes. */
const MAX_BODY_BYTES = 2048;
/** Most an installation can store in one UTC day, so a loop can't fill the table. */
const MAX_EVENTS_PER_INSTALLATION_PER_DAY = 200;

const SECURITY_HEADERS: Record<string, string> = {
  "cache-control": "no-store",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/v1/events") {
      return request.method === "POST" ? receive(request, env) : status(405, { allow: "POST" });
    }
    if (url.pathname === "/v1/stats") {
      return request.method === "GET" ? stats(request, env, url) : status(405, { allow: "GET" });
    }
    if (url.pathname === "/" && request.method === "GET") {
      return new Response(DASHBOARD, {
        headers: {
          ...SECURITY_HEADERS,
          "content-type": "text/html; charset=utf-8",
          "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'",
        },
      });
    }
    return status(404);
  },

  /** Enforces retention. Nothing else writes to the table. */
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    const days = Number(env.RETENTION_DAYS ?? "180");
    const retention = Number.isFinite(days) && days > 0 ? Math.floor(days) : 180;
    const result = await env.DB.prepare(`DELETE FROM events WHERE day < date('now', ?)`)
      .bind(`-${retention} day`)
      .run();
    console.log(`retention: removed ${result.meta.changes ?? 0} rows older than ${retention} days`);
  },
};

async function receive(request: Request, env: Env): Promise<Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return status(413);

  let body: unknown;
  try {
    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) return status(413);
    body = JSON.parse(text);
  } catch {
    return status(400);
  }

  const now = new Date();
  const parsed = parseEvent(body, now);
  if (!parsed.ok) {
    // The reason stays here; the client is told only that it was refused.
    console.log(`refused event: ${parsed.reason}`);
    return status(400);
  }

  const event = parsed.value;
  const day = utcDay(now);

  try {
    await env.DB.prepare(
      `INSERT OR IGNORE INTO events
         (event, installation_id, app_version, build, macos_version, architecture, country, occurred_at, received_at, day)
       SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
        WHERE (SELECT COUNT(*) FROM events WHERE installation_id = ?2 AND day = ?10) < ?11`,
    )
      .bind(
        event.event,
        event.installationID,
        event.appVersion,
        event.build,
        event.macOSVersion,
        event.architecture,
        country((request as { cf?: { country?: unknown } }).cf?.country),
        event.occurredAt,
        now.toISOString(),
        day,
        MAX_EVENTS_PER_INSTALLATION_PER_DAY,
      )
      .run();
  } catch (error) {
    console.log(`storage failed: ${error instanceof Error ? error.message : "unknown"}`);
    return status(503);
  }

  // A duplicate, a capped installation and a fresh row all answer the same
  // way: the app drops the response either way, and silence reveals less.
  return status(204);
}

async function stats(request: Request, env: Env, url: URL): Promise<Response> {
  if (!authorized(request, env)) {
    return status(401, { "www-authenticate": 'Bearer realm="usagenow-telemetry"' });
  }

  const requested = Number(url.searchParams.get("days") ?? "30");
  const days = Number.isFinite(requested) ? Math.min(Math.max(Math.floor(requested), 1), 400) : 30;

  const result = await collectStats(env.DB, days, new Date());
  return new Response(JSON.stringify(result), {
    headers: { ...SECURITY_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

/** Constant-time comparison, so a wrong token leaks nothing through timing. */
function authorized(request: Request, env: Env): boolean {
  const expected = env.STATS_TOKEN;
  if (!expected) return false;

  const header = request.headers.get("authorization") ?? "";
  const provided = header.startsWith("Bearer ") ? header.slice(7) : "";
  const a = new TextEncoder().encode(provided);
  const b = new TextEncoder().encode(expected);
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return difference === 0;
}

function status(code: number, headers: Record<string, string> = {}): Response {
  return new Response(null, { status: code, headers: { ...SECURITY_HEADERS, ...headers } });
}

/**
 * A single page that asks for the token, keeps it in the browser only, and
 * renders /v1/stats. It ships inline so the Worker needs no assets or build.
 */
const DASHBOARD = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>UsageNow telemetry</title>
<style>
  :root { color-scheme: light dark; --bg: #f6f6f8; --card: #fff; --ink: #16161a; --muted: #6b6b76; --line: rgb(0 0 0 / .08); --bar: #0a7aff; }
  @media (prefers-color-scheme: dark) { :root { --bg: #16161a; --card: #1e1e24; --ink: #f2f2f4; --muted: #9a9aa6; --line: rgb(255 255 255 / .1); } }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px 16px 64px; background: var(--bg); color: var(--ink);
         font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
  main { max-width: 900px; margin: 0 auto; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  p.sub { color: var(--muted); margin: 0 0 20px; }
  form { display: flex; gap: 8px; margin-bottom: 20px; flex-wrap: wrap; }
  input, select, button { height: 32px; border-radius: 7px; border: 1px solid var(--line); padding: 0 10px;
                          background: var(--card); color: var(--ink); font: inherit; }
  button { background: var(--bar); color: #fff; border-color: transparent; padding: 0 14px; cursor: pointer; }
  .totals { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin-bottom: 20px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 14px; }
  .card h2 { font-size: 12px; font-weight: 600; color: var(--muted); margin: 0 0 8px; text-transform: uppercase; letter-spacing: .04em; }
  .big { font-size: 26px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }
  table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
  td { padding: 3px 0; }
  td:last-child { text-align: right; color: var(--muted); }
  .spark { display: flex; align-items: flex-end; gap: 2px; height: 56px; margin-top: 4px; }
  .spark i { flex: 1; background: var(--bar); border-radius: 2px 2px 0 0; min-height: 1px; opacity: .85; }
  .empty { color: var(--muted); }
  #error { color: #d23; }
</style>
</head>
<body>
<main>
  <h1>UsageNow telemetry</h1>
  <p class="sub">Anonymous, opt-in events. Nothing here identifies a person or a machine.</p>
  <form id="controls">
    <input id="token" type="password" placeholder="Stats token" autocomplete="off" size="28">
    <select id="days">
      <option value="7">7 days</option>
      <option value="30" selected>30 days</option>
      <option value="90">90 days</option>
      <option value="180">180 days</option>
    </select>
    <button type="submit">Load</button>
  </form>
  <p id="error" hidden></p>
  <div id="out"></div>
</main>
<script>
  const $ = (id) => document.getElementById(id);
  const escape = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  try { $("token").value = localStorage.getItem("token") || ""; } catch {}

  function list(title, rows, total) {
    if (!rows.length) return '<div class="card"><h2>' + title + '</h2><p class="empty">No data yet</p></div>';
    const body = rows.slice(0, 12).map((row) => {
      const share = total ? " · " + Math.round((row.count / total) * 100) + "%" : "";
      return "<tr><td>" + escape(row.name) + "</td><td>" + row.count + share + "</td></tr>";
    }).join("");
    return '<div class="card"><h2>' + title + "</h2><table>" + body + "</table></div>";
  }

  function spark(title, series) {
    if (!series.length) return '<div class="card"><h2>' + title + '</h2><p class="empty">No data yet</p></div>';
    const max = Math.max(...series.map((point) => point.count), 1);
    const bars = series.map((point) =>
      '<i style="height:' + Math.max(2, (point.count / max) * 100) + '%" title="' + escape(point.day) + ": " + point.count + '"></i>'
    ).join("");
    const sum = series.reduce((total, point) => total + point.count, 0);
    return '<div class="card"><h2>' + title + '</h2><div class="big">' + sum + '</div><div class="spark">' + bars + "</div></div>";
  }

  function render(stats) {
    const totals = stats.totals;
    $("out").innerHTML =
      '<div class="totals">' +
        '<div class="card"><h2>Installations</h2><div class="big">' + totals.installations + "</div></div>" +
        '<div class="card"><h2>Active in window</h2><div class="big">' + totals.installationsInWindow + "</div></div>" +
        '<div class="card"><h2>Events stored</h2><div class="big">' + totals.events + "</div></div>" +
        '<div class="card"><h2>Since</h2><div class="big">' + escape(totals.firstSeen || "—") + "</div></div>" +
      "</div>" +
      '<div class="grid">' +
        spark("New installations", stats.installsByDay) +
        spark("Daily active", stats.activeByDay) +
        list("Providers installed", stats.providers, totals.installations) +
        list("App versions", stats.appVersions) +
        list("macOS versions", stats.macOSVersions) +
        list("Architecture", stats.architectures) +
        list("Countries", stats.countries) +
      "</div>";
  }

  $("controls").addEventListener("submit", async (submission) => {
    submission.preventDefault();
    const token = $("token").value.trim();
    try { localStorage.setItem("token", token); } catch {}
    $("error").hidden = true;
    try {
      const response = await fetch("/v1/stats?days=" + $("days").value, { headers: { authorization: "Bearer " + token } });
      if (!response.ok) throw new Error(response.status === 401 ? "Wrong token" : "Request failed (" + response.status + ")");
      render(await response.json());
    } catch (failure) {
      $("out").innerHTML = "";
      $("error").textContent = failure.message;
      $("error").hidden = false;
    }
  });

  if ($("token").value) $("controls").requestSubmit();
</script>
</body>
</html>`;
