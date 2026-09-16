/**
 * Validation for the one request body UsageNow ever sends.
 *
 * The app's `TelemetryPayload` is a closed set of seven fields. This mirrors
 * it exactly and rejects anything else, so a payload carrying provider data —
 * tokens, quotas, model names, paths — can never be stored, even if some
 * future client sent one by mistake.
 */

/** Every event the app may report, matching `TelemetryEvent` in the app. */
export const EVENTS = [
  "first_launch",
  "app_active",
  "app_updated",
  "codex_detected",
  "claude_detected",
  "gemini_detected",
  "antigravity_detected",
] as const;

export type EventName = (typeof EVENTS)[number];

const ARCHITECTURES = ["arm64", "x86_64"] as const;

/** The exact set of keys a body must have — no more, no fewer. */
const FIELDS = [
  "event",
  "installation_id",
  "app_version",
  "build",
  "macos_version",
  "architecture",
  "timestamp",
] as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
/** Digits, dots and short suffixes only: "0.3.0", "15.6.1", "1". */
const VERSION = /^[0-9][0-9A-Za-z.\-+]{0,31}$/;

/** How far a client clock may be off before the event is refused. */
const FUTURE_TOLERANCE_MS = 24 * 60 * 60 * 1000;
const PAST_TOLERANCE_MS = 30 * 24 * 60 * 60 * 1000;

export interface TelemetryEvent {
  event: EventName;
  installationID: string;
  appVersion: string;
  build: string;
  macOSVersion: string;
  architecture: string;
  /** The client's timestamp, normalized to ISO 8601 in UTC. */
  occurredAt: string;
}

export type ParseResult =
  | { ok: true; value: TelemetryEvent }
  | { ok: false; reason: string };

/**
 * Parses a request body into an event, or explains why it isn't one.
 *
 * The reason is for the Worker's own logs; it is never sent back, so a
 * client learns only that the body was refused.
 */
export function parseEvent(body: unknown, now: Date): ParseResult {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, reason: "body is not an object" };
  }

  const keys = Object.keys(body);
  if (keys.length !== FIELDS.length || !FIELDS.every((field) => keys.includes(field))) {
    return { ok: false, reason: `unexpected fields: ${keys.sort().join(",")}` };
  }

  const record = body as Record<string, unknown>;
  for (const field of FIELDS) {
    if (typeof record[field] !== "string") return { ok: false, reason: `${field} is not a string` };
  }

  const event = record.event as string;
  if (!(EVENTS as readonly string[]).includes(event)) {
    return { ok: false, reason: `unknown event: ${event.slice(0, 64)}` };
  }

  const installationID = (record.installation_id as string).toLowerCase();
  if (!UUID.test(installationID)) return { ok: false, reason: "installation_id is not a UUID" };

  const appVersion = record.app_version as string;
  const build = record.build as string;
  const macOSVersion = record.macos_version as string;
  if (!VERSION.test(appVersion)) return { ok: false, reason: "app_version is malformed" };
  if (!VERSION.test(build)) return { ok: false, reason: "build is malformed" };
  if (!VERSION.test(macOSVersion)) return { ok: false, reason: "macos_version is malformed" };

  const architecture = record.architecture as string;
  if (!(ARCHITECTURES as readonly string[]).includes(architecture)) {
    return { ok: false, reason: "unknown architecture" };
  }

  const occurred = new Date(record.timestamp as string);
  if (Number.isNaN(occurred.getTime())) return { ok: false, reason: "timestamp is not a date" };
  const drift = occurred.getTime() - now.getTime();
  if (drift > FUTURE_TOLERANCE_MS) return { ok: false, reason: "timestamp is in the future" };
  if (-drift > PAST_TOLERANCE_MS) return { ok: false, reason: "timestamp is too old" };

  return {
    ok: true,
    value: {
      event: event as EventName,
      installationID,
      appVersion,
      build,
      macOSVersion,
      architecture,
      occurredAt: occurred.toISOString(),
    },
  };
}

/**
 * The two-letter country Cloudflare resolved for the request, or `null`.
 *
 * This is the only thing derived from the connection, and it is derived
 * here rather than sent by the app. Cloudflare uses "T1" for Tor and "XX"
 * when it doesn't know; neither is a country, so both become `null`.
 */
export function country(value: unknown): string | null {
  if (typeof value !== "string" || !/^[A-Z]{2}$/.test(value)) return null;
  return value === "T1" || value === "XX" ? null : value;
}

/** The UTC day an event is counted under, as `YYYY-MM-DD`. */
export function utcDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}
