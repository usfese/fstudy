CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('recruiting', 'in_progress', 'closed')),
  capacity INTEGER NOT NULL CHECK (capacity BETWEEN 1 AND 50),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX projects_status_updated_idx ON projects(status, updated_at);
CREATE INDEX projects_owner_idx ON projects(owner_id, updated_at);

CREATE TABLE project_tags (
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY(project_id, tag_id)
);

CREATE INDEX project_tags_tag_idx ON project_tags(tag_id);

CREATE TABLE project_applications (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  applicant_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')),
  created_at TEXT NOT NULL,
  responded_at TEXT,
  UNIQUE(project_id, applicant_id)
);

CREATE INDEX project_applications_project_idx ON project_applications(project_id, status);
CREATE INDEX project_applications_applicant_idx ON project_applications(applicant_id, status);

CREATE TABLE project_members (
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL,
  PRIMARY KEY(project_id, user_id)
);

CREATE INDEX project_members_user_idx ON project_members(user_id);
