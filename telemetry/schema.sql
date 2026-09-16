-- The complete storage for UsageNow telemetry.
--
-- One row per event, holding the seven fields the app sends plus the country
-- Cloudflare resolved and the time the Worker received it. IP addresses, user
-- agents and request headers are never written here.

CREATE TABLE IF NOT EXISTS events (
    id              INTEGER PRIMARY KEY,
    event           TEXT NOT NULL,
    installation_id TEXT NOT NULL,
    app_version     TEXT NOT NULL,
    build           TEXT NOT NULL,
    macos_version   TEXT NOT NULL,
    architecture    TEXT NOT NULL,
    -- Two-letter country resolved from the connection, or NULL when unknown.
    country         TEXT,
    -- When the app says the event happened, ISO 8601 in UTC.
    occurred_at     TEXT NOT NULL,
    -- When this Worker stored it, ISO 8601 in UTC.
    received_at     TEXT NOT NULL,
    -- UTC date of received_at, so every rollup groups on an indexed column.
    day             TEXT NOT NULL
);

-- A retry that reaches us twice must not count twice.
CREATE UNIQUE INDEX IF NOT EXISTS events_identity
    ON events (installation_id, event, occurred_at);

CREATE INDEX IF NOT EXISTS events_day ON events (day);
CREATE INDEX IF NOT EXISTS events_event_day ON events (event, day);
-- Supports both the per-installation flood cap and distinct-installation counts.
CREATE INDEX IF NOT EXISTS events_installation_day ON events (installation_id, day);
