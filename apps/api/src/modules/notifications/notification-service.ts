import type { SqlDatabase } from '../../core/types.js';

type NotificationRow = {
  id: string;
  kind: string;
  title: string;
  body: string;
  target_path: string;
  created_at: string;
  read_at: string | null;
};

export class NotificationService {
  constructor(private readonly database: SqlDatabase) {}

  async create(input: {
    recipientId: string;
    actorId: string;
    kind: 'friend_request' | 'availability_invite' | 'project_application' | 'forum_reply';
    title: string;
    body: string;
    targetPath: string;
  }) {
    if (input.recipientId === input.actorId) return;
    try {
      await this.database.execute({
        sql: `INSERT INTO notifications
          (id, recipient_id, actor_id, kind, title, body, target_path, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        params: [
          crypto.randomUUID(), input.recipientId, input.actorId, input.kind,
          input.title, input.body, input.targetPath, new Date().toISOString(),
        ],
      });
    } catch (error) {
      // Notifications are best-effort; a delivery/storage hiccup must not make
      // the underlying friend/project/forum action look like it failed.
      console.error('Notification persistence failed', error instanceof Error ? error.message : 'unknown');
    }
  }

  async list(userId: string) {
    const [items, unread] = await Promise.all([
      this.database.execute<NotificationRow>({
        sql: `SELECT id, kind, title, body, target_path, created_at, read_at
              FROM notifications WHERE recipient_id = ?
              ORDER BY created_at DESC LIMIT 100`,
        params: [userId],
      }),
      this.database.execute<{ count: number }>({
        sql: 'SELECT COUNT(*) AS count FROM notifications WHERE recipient_id = ? AND read_at IS NULL',
        params: [userId],
      }),
    ]);
    return {
      unreadCount: unread.rows[0]?.count ?? 0,
      notifications: items.rows.map((row) => ({
        id: row.id,
        kind: row.kind,
        title: row.title,
        body: row.body,
        targetPath: row.target_path,
        createdAt: row.created_at,
        readAt: row.read_at,
      })),
    };
  }

  async markRead(userId: string, id?: string) {
    await this.database.execute({
      sql: id
        ? 'UPDATE notifications SET read_at = ? WHERE id = ? AND recipient_id = ? AND read_at IS NULL'
        : 'UPDATE notifications SET read_at = ? WHERE recipient_id = ? AND read_at IS NULL',
      params: id
        ? [new Date().toISOString(), id, userId]
        : [new Date().toISOString(), userId],
    });
  }
}
