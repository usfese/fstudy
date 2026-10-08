CREATE TABLE forum_posts (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('general', 'course', 'campus', 'experience')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX forum_posts_category_updated_idx ON forum_posts(category, updated_at);
CREATE INDEX forum_posts_author_created_idx ON forum_posts(author_id, created_at);

CREATE TABLE forum_replies (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES forum_posts(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX forum_replies_post_created_idx ON forum_replies(post_id, created_at);
CREATE INDEX forum_replies_author_created_idx ON forum_replies(author_id, created_at);
