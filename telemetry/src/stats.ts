/**
 * Aggregates for the dashboard.
 *
 * Everything here counts distinct installations or events. No query returns
 * a row about one installation, because nothing in the data would be worth
 * looking at that way.
 */

import { EVENTS } from "./validate";

export interface Stats {
  /** The window these numbers cover, in days. */
  days: number;
  generatedAt: string;
  totals: {
    installations: number;
    installationsInWindow: number;
    events: number;
    firstSeen: string | null;
  };
  /** New installations per day, oldest first. */
  installsByDay: Array<{ day: string; count: number }>;
  /** Installations active per day, oldest first. */
  activeByDay: Array<{ day: string; count: number }>;
  appVersions: Array<{ name: string; count: number }>;
  macOSVersions: Array<{ name: string; count: number }>;
  architectures: Array<{ name: string; count: number }>;
  countries: Array<{ name: string; count: number }>;
  /** How many installations reported each provider as installed. */
  providers: Array<{ name: string; count: number }>;
}

type Row = Record<string, unknown>;

const number = (value: unknown): number => (typeof value === "number" ? value : Number(value ?? 0));
const text = (value: unknown): string => (typeof value === "string" ? value : String(value ?? ""));

const providerEvents = EVENTS.filter((event) => event.endsWith("_detected"));

export async function collectStats(db: D1Database, days: number, now: Date): Promise<Stats> {
  const since = new Date(now.getTime() - days * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  const byDay = (event: string, distinct: boolean) =>
    db
      .prepare(
        `SELECT day, COUNT(${distinct ? "DISTINCT installation_id" : "*"}) AS count
           FROM events WHERE event = ? AND day >= ? GROUP BY day ORDER BY day`,
      )
      .bind(event, since);

  const breakdown = (column: string) =>
    db
      .prepare(
        `SELECT ${column} AS name, COUNT(DISTINCT installation_id) AS count
           FROM events WHERE day >= ? AND ${column} IS NOT NULL
          GROUP BY ${column} ORDER BY count DESC, name`,
      )
      .bind(since);

  const results = await db.batch([
    db.prepare(
      `SELECT COUNT(DISTINCT installation_id) AS installations,
              COUNT(*) AS events,
              MIN(day) AS first_seen FROM events`,
    ),
    db.prepare(`SELECT COUNT(DISTINCT installation_id) AS installations FROM events WHERE day >= ?`).bind(since),
    byDay("first_launch", false),
    byDay("app_active", true),
    breakdown("app_version"),
    breakdown("macos_version"),
    breakdown("architecture"),
    breakdown("country"),
    db
      .prepare(
        `SELECT event AS name, COUNT(DISTINCT installation_id) AS count
           FROM events WHERE event IN (${providerEvents.map(() => "?").join(",")})
          GROUP BY event ORDER BY count DESC`,
      )
      .bind(...providerEvents),
  ]);

  const rows = (index: number): Row[] => (results[index]?.results ?? []) as Row[];
  const series = (index: number) => rows(index).map((row) => ({ day: text(row.day), count: number(row.count) }));
  const named = (index: number) => rows(index).map((row) => ({ name: text(row.name), count: number(row.count) }));

  const overall = rows(0)[0] ?? {};
  const firstSeen = overall.first_seen;

  return {
    days,
    generatedAt: now.toISOString(),
    totals: {
      installations: number(overall.installations),
      installationsInWindow: number(rows(1)[0]?.installations),
      events: number(overall.events),
      firstSeen: typeof firstSeen === "string" ? firstSeen : null,
    },
    installsByDay: series(2),
    activeByDay: series(3),
    appVersions: named(4),
    macOSVersions: named(5),
    architectures: named(6),
    countries: named(7),
    providers: named(8).map((row) => ({ ...row, name: row.name.replace(/_detected$/, "") })),
  };
}
