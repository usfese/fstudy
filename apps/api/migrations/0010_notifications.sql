CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  kind TEXT NOT NULL CHECK (kind IN ('friend_request', 'availability_invite', 'project_application', 'forum_reply')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  target_path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  read_at TEXT
);
CREATE INDEX notifications_recipient_created_idx ON notifications(recipient_id, created_at DESC);
CREATE INDEX notifications_recipient_unread_idx ON notifications(recipient_id, read_at, created_at DESC);
