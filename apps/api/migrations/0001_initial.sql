PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  department_id TEXT,
  bio TEXT NOT NULL DEFAULT '',
  discoverable INTEGER NOT NULL DEFAULT 0 CHECK (discoverable IN (0, 1)),
  schedule_visibility TEXT NOT NULL DEFAULT 'busy_only' CHECK (schedule_visibility IN ('private', 'busy_only', 'course_name', 'full')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
  created_at TEXT NOT NULL
);

CREATE TABLE student_identities (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  student_id_hash TEXT NOT NULL UNIQUE,
  verified_department_id TEXT,
  verified_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE credentials (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX sessions_user_idx ON sessions(user_id);
CREATE INDEX sessions_token_idx ON sessions(token_hash);

CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL CHECK (category IN ('interest', 'field', 'goal')),
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  UNIQUE(category, name)
);

CREATE TABLE user_tags (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  is_core INTEGER NOT NULL DEFAULT 0 CHECK (is_core IN (0, 1)),
  visible INTEGER NOT NULL DEFAULT 1 CHECK (visible IN (0, 1)),
  used_for_recommendation INTEGER NOT NULL DEFAULT 1 CHECK (used_for_recommendation IN (0, 1)),
  PRIMARY KEY(user_id, tag_id)
);
CREATE INDEX user_tags_tag_idx ON user_tags(tag_id);

CREATE TABLE courses (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  teacher TEXT,
  color TEXT NOT NULL DEFAULT '#4F46E5',
  created_at TEXT NOT NULL
);
CREATE INDEX courses_user_idx ON courses(user_id);

CREATE TABLE course_meetings (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  start_minute INTEGER NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
  end_minute INTEGER NOT NULL CHECK (end_minute BETWEEN 1 AND 1440),
  start_week INTEGER NOT NULL CHECK (start_week >= 1),
  end_week INTEGER NOT NULL CHECK (end_week >= start_week),
  week_parity TEXT NOT NULL DEFAULT 'all' CHECK (week_parity IN ('all', 'odd', 'even')),
  campus TEXT,
  building TEXT,
  room TEXT,
  CHECK (end_minute > start_minute)
);
CREATE INDEX course_meetings_course_idx ON course_meetings(course_id);
CREATE INDEX course_meetings_time_idx ON course_meetings(weekday, start_minute, end_minute);

CREATE TABLE assignments (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  course_id TEXT REFERENCES courses(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  due_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX assignments_user_due_idx ON assignments(user_id, due_at);

INSERT INTO tags (id, category, name) VALUES
  ('interest-photography', 'interest', '摄影'),
  ('interest-basketball', 'interest', '篮球'),
  ('interest-boardgame', 'interest', '桌游'),
  ('field-frontend', 'field', '前端'),
  ('field-backend', 'field', '后端'),
  ('field-ai', 'field', '人工智能'),
  ('field-security', 'field', '网络安全'),
  ('goal-project', 'goal', '找项目队友'),
  ('goal-study', 'goal', '找学习搭子'),
  ('goal-sport', 'goal', '找运动搭子');
