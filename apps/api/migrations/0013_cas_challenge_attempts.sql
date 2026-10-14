CREATE INDEX cas_password_challenges_attempts_idx
  ON cas_password_challenges(student_id_hash, attempt_count, expires_at);
