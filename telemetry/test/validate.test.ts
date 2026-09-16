import { describe, expect, it } from "vitest";

import { country, parseEvent, utcDay } from "../src/validate";

const now = new Date("2026-09-16T12:00:00Z");

/** Exactly what the app's `TelemetryPayload` encodes. */
const payload = () => ({
  event: "app_active",
  installation_id: "3f2a1b7c-5d4e-4f8a-9b0c-1d2e3f4a5b6c",
  app_version: "0.3.0",
  build: "1",
  macos_version: "15.6.1",
  architecture: "arm64",
  timestamp: "2026-09-16T11:59:30Z",
});

describe("parseEvent", () => {
  it("accepts the payload the app sends", () => {
    const result = parseEvent(payload(), now);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.event).toBe("app_active");
    expect(result.value.occurredAt).toBe("2026-09-16T11:59:30.000Z");
  });

  it("accepts every event the app can report", () => {
    for (const event of [
      "first_launch",
      "app_active",
      "app_updated",
      "codex_detected",
      "claude_detected",
      "gemini_detected",
      "antigravity_detected",
    ]) {
      expect(parseEvent({ ...payload(), event }, now).ok).toBe(true);
    }
  });

  it("refuses an event name it doesn't know", () => {
    expect(parseEvent({ ...payload(), event: "tokens_used" }, now).ok).toBe(false);
  });

  it("refuses a body carrying anything beyond the seven fields", () => {
    const extra = { ...payload(), tokens_today: 12000, model: "claude-fable-5-1" };
    expect(parseEvent(extra, now).ok).toBe(false);
  });

  it("refuses a body missing a field", () => {
    const { build, ...rest } = payload();
    void build;
    expect(parseEvent(rest, now).ok).toBe(false);
  });

  it("refuses a non-string field", () => {
    expect(parseEvent({ ...payload(), build: 1 }, now).ok).toBe(false);
  });

  it("refuses an installation id that isn't a UUID", () => {
    expect(parseEvent({ ...payload(), installation_id: "umid@example.com" }, now).ok).toBe(false);
    expect(parseEvent({ ...payload(), installation_id: "C02XK1VVJG5H" }, now).ok).toBe(false);
  });

  it("normalizes an uppercase UUID", () => {
    const result = parseEvent({ ...payload(), installation_id: payload().installation_id.toUpperCase() }, now);
    expect(result.ok && result.value.installationID).toBe(payload().installation_id);
  });

  it("refuses versions that aren't versions", () => {
    expect(parseEvent({ ...payload(), app_version: "/Users/umid/.claude" }, now).ok).toBe(false);
    expect(parseEvent({ ...payload(), macos_version: "x".repeat(64) }, now).ok).toBe(false);
  });

  it("refuses an unknown architecture", () => {
    expect(parseEvent({ ...payload(), architecture: "riscv" }, now).ok).toBe(false);
  });

  it("refuses a timestamp that is unparseable, far future, or far past", () => {
    expect(parseEvent({ ...payload(), timestamp: "yesterday" }, now).ok).toBe(false);
    expect(parseEvent({ ...payload(), timestamp: "2027-01-01T00:00:00Z" }, now).ok).toBe(false);
    expect(parseEvent({ ...payload(), timestamp: "2026-01-01T00:00:00Z" }, now).ok).toBe(false);
  });

  it("allows a clock that is a little ahead", () => {
    expect(parseEvent({ ...payload(), timestamp: "2026-09-16T18:00:00Z" }, now).ok).toBe(true);
  });

  it("refuses a body that isn't an object", () => {
    expect(parseEvent(null, now).ok).toBe(false);
    expect(parseEvent([payload()], now).ok).toBe(false);
    expect(parseEvent("app_active", now).ok).toBe(false);
  });
});

describe("country", () => {
  it("keeps a two-letter country", () => {
    expect(country("UZ")).toBe("UZ");
  });

  it("drops Tor, unknown, and anything else", () => {
    expect(country("T1")).toBeNull();
    expect(country("XX")).toBeNull();
    expect(country("Uzbekistan")).toBeNull();
    expect(country(undefined)).toBeNull();
  });
});

describe("utcDay", () => {
  it("is the UTC date, whatever the local zone", () => {
    expect(utcDay(new Date("2026-09-16T23:30:00Z"))).toBe("2026-09-16");
    expect(utcDay(new Date("2026-09-17T00:30:00Z"))).toBe("2026-09-17");
  });
});
