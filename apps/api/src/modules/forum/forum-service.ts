import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

type PostRow = {
  id: string;
  author_id: string;
  author_name: string;
  category: string;
  title: string;
  body: string;
  created_at: string;
  updated_at: string;
  reply_count: number;
};

type ReplyRow = {
  id: string;
  author_id: string;
  author_name: string;
  body: string;
  created_at: string;
};

export class ForumService {
  constructor(private readonly database: SqlDatabase) {}

  async list(category?: string) {
    const result = await this.database.execute<PostRow>({
      sql: `SELECT fp.id, fp.author_id, u.display_name AS author_name, fp.category,
                   fp.title, fp.body, fp.created_at, fp.updated_at,
                   (SELECT COUNT(*) FROM forum_replies fr WHERE fr.post_id = fp.id AND fr.moderation_status = 'visible') AS reply_count
            FROM forum_posts fp JOIN users u ON u.id = fp.author_id
            WHERE fp.moderation_status = 'visible'
            ${category ? 'AND fp.category = ?' : ''}
            ORDER BY fp.updated_at DESC LIMIT 100`,
      params: category ? [category] : [],
    });
    return result.rows.map((post) => this.mapPost(post));
  }

  async get(postId: string) {
    const posts = await this.database.execute<PostRow>({
      sql: `SELECT fp.id, fp.author_id, u.display_name AS author_name, fp.category,
                   fp.title, fp.body, fp.created_at, fp.updated_at,
                   (SELECT COUNT(*) FROM forum_replies fr WHERE fr.post_id = fp.id AND fr.moderation_status = 'visible') AS reply_count
            FROM forum_posts fp JOIN users u ON u.id = fp.author_id
            WHERE fp.id = ? AND fp.moderation_status = 'visible'`,
      params: [postId],
    });
    const post = posts.rows[0];
    if (!post) throw new DomainError('forum_post_not_found', '帖子不存在', 404);
    const replies = await this.database.execute<ReplyRow>({
      sql: `SELECT fr.id, fr.author_id, u.display_name AS author_name, fr.body, fr.created_at
            FROM forum_replies fr JOIN users u ON u.id = fr.author_id
            WHERE fr.post_id = ? AND fr.moderation_status = 'visible' ORDER BY fr.created_at ASC`,
      params: [postId],
    });
    return {
      post: this.mapPost(post),
      replies: replies.rows.map((reply) => ({
        id: reply.id,
        authorId: reply.author_id,
        authorName: reply.author_name,
        body: reply.body,
        createdAt: reply.created_at,
      })),
    };
  }

  async createPost(userId: string, input: { category: string; title: string; body: string }) {
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const recent = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM forum_posts WHERE author_id = ? AND created_at >= ?',
      params: [userId, since],
    });
    if ((recent.rows[0]?.count ?? 0) >= 10) {
      throw new DomainError('forum_post_rate_limited', '每天最多发布 10 篇帖子', 429);
    }
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    await this.database.execute({
      sql: `INSERT INTO forum_posts
            (id, author_id, category, title, body, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)`,
      params: [id, userId, input.category, input.title, input.body, now, now],
    });
    return { id };
  }

  async createReply(userId: string, postId: string, body: string) {
    const post = await this.database.execute<{ id: string }>({
      sql: "SELECT id FROM forum_posts WHERE id = ? AND moderation_status = 'visible'",
      params: [postId],
    });
    if (!post.rows[0]) throw new DomainError('forum_post_not_found', '帖子不存在', 404);
    const since = new Date(Date.now() - 3_600_000).toISOString();
    const recent = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM forum_replies WHERE author_id = ? AND created_at >= ?',
      params: [userId, since],
    });
    if ((recent.rows[0]?.count ?? 0) >= 30) {
      throw new DomainError('forum_reply_rate_limited', '每小时最多回复 30 次', 429);
    }
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    await this.database.batch([
      {
        sql: 'INSERT INTO forum_replies (id, post_id, author_id, body, created_at) VALUES (?, ?, ?, ?, ?)',
        params: [id, postId, userId, body, now],
      },
      {
        sql: 'UPDATE forum_posts SET updated_at = ? WHERE id = ?',
        params: [now, postId],
      },
    ]);
    return { id };
  }

  private mapPost(post: PostRow) {
    return {
      id: post.id,
      authorId: post.author_id,
      authorName: post.author_name,
      category: post.category,
      title: post.title,
      body: post.body,
      createdAt: post.created_at,
      updatedAt: post.updated_at,
      replyCount: post.reply_count,
    };
  }
}
