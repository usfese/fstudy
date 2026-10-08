import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

type RequestRow = {
  id: string;
  sender_id: string;
  receiver_id: string;
  status: string;
};

type RequestListRow = {
  id: string;
  user_id: string;
  display_name: string;
  department_id: string | null;
  created_at: string;
};

type FriendRow = {
  id: string;
  display_name: string;
  department_id: string | null;
  bio: string;
  friends_since: string;
};

function pairKey(first: string, second: string): string {
  return [first, second].sort().join(':');
}

export class FriendService {
  constructor(private readonly database: SqlDatabase) {}

  async send(userId: string, targetUserId: string) {
    if (userId === targetUserId) {
      throw new DomainError('cannot_friend_self', '不能向自己发送好友请求', 400);
    }
    const target = await this.database.execute<{ id: string }>({
      sql: `SELECT id FROM users
            WHERE id = ? AND status = 'active' AND discoverable = 1`,
      params: [targetUserId],
    });
    if (!target.rows[0]) {
      throw new DomainError('user_not_available', '该用户当前不可添加', 404);
    }

    const key = pairKey(userId, targetUserId);
    const existing = await this.database.execute<RequestRow>({
      sql: 'SELECT id, sender_id, receiver_id, status FROM friend_requests WHERE pair_key = ?',
      params: [key],
    });
    const row = existing.rows[0];
    if (row?.status === 'accepted') {
      throw new DomainError('already_friends', '你们已经是好友', 409);
    }
    if (row?.status === 'pending') {
      throw new DomainError(
        row.sender_id === userId ? 'request_already_sent' : 'incoming_request_exists',
        row.sender_id === userId ? '好友请求已发送' : '对方已经向你发送了好友请求',
        409,
      );
    }

    const id = row?.id ?? crypto.randomUUID();
    const now = new Date().toISOString();
    if (row) {
      await this.database.execute({
        sql: `UPDATE friend_requests SET sender_id = ?, receiver_id = ?, status = 'pending',
              created_at = ?, responded_at = NULL WHERE id = ?`,
        params: [userId, targetUserId, now, id],
      });
    } else {
      await this.database.execute({
        sql: `INSERT INTO friend_requests
              (id, pair_key, sender_id, receiver_id, status, created_at)
              VALUES (?, ?, ?, ?, 'pending', ?)`,
        params: [id, key, userId, targetUserId, now],
      });
    }
    return { id };
  }

  async respond(userId: string, requestId: string, action: 'accept' | 'reject' | 'cancel') {
    const result = await this.database.execute<RequestRow>({
      sql: `SELECT id, sender_id, receiver_id, status FROM friend_requests WHERE id = ?`,
      params: [requestId],
    });
    const request = result.rows[0];
    if (!request || request.status !== 'pending') {
      throw new DomainError('friend_request_not_found', '好友请求不存在或已处理', 404);
    }
    if (action === 'cancel' && request.sender_id !== userId) {
      throw new DomainError('friend_request_forbidden', '只能取消自己发出的请求', 403);
    }
    if (action !== 'cancel' && request.receiver_id !== userId) {
      throw new DomainError('friend_request_forbidden', '只能处理收到的请求', 403);
    }

    const status = action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : 'canceled';
    const now = new Date().toISOString();
    const statements = [{
      sql: 'UPDATE friend_requests SET status = ?, responded_at = ? WHERE id = ?',
      params: [status, now, requestId],
    }];
    if (action === 'accept') {
      const userA = request.sender_id < request.receiver_id
        ? request.sender_id
        : request.receiver_id;
      const userB = request.sender_id < request.receiver_id
        ? request.receiver_id
        : request.sender_id;
      statements.push({
        sql: `INSERT INTO friendships (pair_key, user_a_id, user_b_id, created_at)
              VALUES (?, ?, ?, ?)`,
        params: [pairKey(userA, userB), userA, userB, now],
      });
    }
    await this.database.batch(statements);
  }

  async list(userId: string) {
    const [friends, incoming, outgoing] = await Promise.all([
      this.database.execute<FriendRow>({
        sql: `SELECT u.id, u.display_name, u.department_id, u.bio, f.created_at AS friends_since
              FROM friendships f
              JOIN users u ON u.id = CASE WHEN f.user_a_id = ? THEN f.user_b_id ELSE f.user_a_id END
              WHERE (f.user_a_id = ? OR f.user_b_id = ?) AND u.status = 'active'
              ORDER BY u.display_name`,
        params: [userId, userId, userId],
      }),
      this.database.execute<RequestListRow>({
        sql: `SELECT r.id, u.id AS user_id, u.display_name, u.department_id, r.created_at
              FROM friend_requests r JOIN users u ON u.id = r.sender_id
              WHERE r.receiver_id = ? AND r.status = 'pending' ORDER BY r.created_at DESC`,
        params: [userId],
      }),
      this.database.execute<RequestListRow>({
        sql: `SELECT r.id, u.id AS user_id, u.display_name, u.department_id, r.created_at
              FROM friend_requests r JOIN users u ON u.id = r.receiver_id
              WHERE r.sender_id = ? AND r.status = 'pending' ORDER BY r.created_at DESC`,
        params: [userId],
      }),
    ]);
    const mapRequest = (row: RequestListRow) => ({
      id: row.id,
      userId: row.user_id,
      displayName: row.display_name,
      departmentId: row.department_id,
      createdAt: row.created_at,
    });
    return {
      friends: friends.rows.map((row) => ({
        id: row.id,
        displayName: row.display_name,
        departmentId: row.department_id,
        bio: row.bio,
        friendsSince: row.friends_since,
      })),
      incoming: incoming.rows.map(mapRequest),
      outgoing: outgoing.rows.map(mapRequest),
    };
  }
}
