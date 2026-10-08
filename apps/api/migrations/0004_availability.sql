CREATE TABLE availability_invites (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'canceled')),
  created_at TEXT NOT NULL,
  responded_at TEXT,
  CHECK (sender_id <> receiver_id),
  CHECK (ends_at > starts_at)
);

CREATE INDEX availability_invites_sender_idx
  ON availability_invites(sender_id, status, starts_at);
CREATE INDEX availability_invites_receiver_idx
  ON availability_invites(receiver_id, status, starts_at);
