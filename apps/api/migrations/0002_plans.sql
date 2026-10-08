CREATE TABLE plans (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  reminder_minutes INTEGER CHECK (reminder_minutes IS NULL OR reminder_minutes BETWEEN 0 AND 10080),
  completed_at TEXT,
  created_at TEXT NOT NULL,
  CHECK (ends_at > starts_at)
);

CREATE INDEX plans_user_start_idx ON plans(user_id, starts_at);
