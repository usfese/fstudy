CREATE TABLE admin_accounts (
  username TEXT PRIMARY KEY,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE admin_sessions (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX admin_sessions_token_idx ON admin_sessions(token_hash);

CREATE TABLE admin_login_throttles (
  username_key TEXT PRIMARY KEY,
  failure_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TEXT NOT NULL,
  blocked_until TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE admin_audit_log (
  id TEXT PRIMARY KEY,
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);
CREATE INDEX admin_audit_created_idx ON admin_audit_log(created_at DESC);

CREATE TABLE content_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK (target_type IN ('forum_post', 'forum_reply', 'project')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'dismissed')),
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  reviewed_by TEXT
);
CREATE INDEX content_reports_status_created_idx ON content_reports(status, created_at DESC);
CREATE INDEX content_reports_target_idx ON content_reports(target_type, target_id);

ALTER TABLE forum_posts ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'visible'
  CHECK (moderation_status IN ('visible', 'hidden'));
ALTER TABLE forum_replies ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'visible'
  CHECK (moderation_status IN ('visible', 'hidden'));
ALTER TABLE projects ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'visible'
  CHECK (moderation_status IN ('visible', 'hidden'));
