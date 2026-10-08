CREATE TABLE friend_requests (
  id TEXT PRIMARY KEY,
  pair_key TEXT NOT NULL UNIQUE,
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'canceled')),
  created_at TEXT NOT NULL,
  responded_at TEXT,
  CHECK (sender_id <> receiver_id)
);

CREATE INDEX friend_requests_sender_idx ON friend_requests(sender_id, status);
CREATE INDEX friend_requests_receiver_idx ON friend_requests(receiver_id, status);

CREATE TABLE friendships (
  pair_key TEXT PRIMARY KEY,
  user_a_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  CHECK (user_a_id <> user_b_id)
);

CREATE INDEX friendships_user_a_idx ON friendships(user_a_id);
CREATE INDEX friendships_user_b_idx ON friendships(user_b_id);
