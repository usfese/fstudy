CREATE TABLE invite_codes (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL CHECK (source IN ('user', 'admin')),
  issued_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  issued_month TEXT NOT NULL,
  created_at TEXT NOT NULL,
  used_by TEXT,
  used_at TEXT
);
CREATE INDEX invite_codes_issuer_month_idx ON invite_codes(issued_by, issued_month);

CREATE TABLE user_emails (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
