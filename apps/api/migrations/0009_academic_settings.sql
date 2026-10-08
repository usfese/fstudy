CREATE TABLE user_academic_settings (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  semester_start_date TEXT,
  updated_at TEXT NOT NULL
);
