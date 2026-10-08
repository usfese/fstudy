CREATE TABLE auth_throttles (
  throttle_key TEXT PRIMARY KEY,
  failure_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TEXT NOT NULL,
  blocked_until TEXT,
  updated_at TEXT NOT NULL
);

CREATE INDEX auth_throttles_updated_idx ON auth_throttles(updated_at);
