CREATE TABLE cas_password_challenges (
  challenge_hash TEXT PRIMARY KEY,
  student_id_hash TEXT NOT NULL,
  encrypted_state TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  consumed_at TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX cas_password_challenges_expiry_idx ON cas_password_challenges(expires_at);
CREATE INDEX cas_password_challenges_student_created_idx ON cas_password_challenges(student_id_hash, created_at DESC);
