CREATE TABLE cas_login_states (
  state_hash TEXT PRIMARY KEY,
  return_origin TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  used_at TEXT
);
CREATE INDEX cas_login_states_expiry_idx ON cas_login_states(expires_at);

CREATE TABLE cas_login_codes (
  code_hash TEXT PRIMARY KEY,
  state_hash TEXT NOT NULL,
  student_id_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  used_at TEXT
);
CREATE INDEX cas_login_codes_expiry_idx ON cas_login_codes(expires_at);
