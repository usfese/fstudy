-- Username-only accounts (ADR-023). `student_identities` and its
-- `student_id_hash` column stay in the schema as a reserved extension point,
-- but new accounts no longer write to that table.

ALTER TABLE users ADD COLUMN username TEXT;

-- Existing beta accounts get a stable, non-identifying username. Password
-- logins for these accounts use the new generated username.
UPDATE users
SET username = 'user_' || lower(substr(replace(id, '-', ''), 1, 8))
WHERE username IS NULL;

CREATE UNIQUE INDEX users_username_unique ON users(username);
