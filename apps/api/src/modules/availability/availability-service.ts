import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';
import { NotificationService } from '../notifications/notification-service.js';

type CourseBusyRow = { user_id: string; name: string; start_minute: number; end_minute: number };
type PlanBusyRow = { user_id: string; title: string; starts_at: string; ends_at: string };
type Visibility = 'private' | 'busy_only' | 'course_name' | 'full';
type InviteRow = {
  id: string;
  sender_id: string;
  receiver_id: string;
  starts_at: string;
  ends_at: string;
  title: string;
  status: string;
  created_at: string;
};
type InviteListRow = InviteRow & {
  other_user_id: string;
  display_name: string;
};

type Interval = { startMinute: number; endMinute: number };

function pairKey(first: string, second: string): string {
  return [first, second].sort().join(':');
}

function minutesWithin(startsAt: string, endsAt: string, dayStart: Date, dayEnd: Date): Interval {
  return {
    startMinute: Math.floor((Math.max(new Date(startsAt).getTime(), dayStart.getTime()) - dayStart.getTime()) / 60_000),
    endMinute: Math.ceil((Math.min(new Date(endsAt).getTime(), dayEnd.getTime()) - dayStart.getTime()) / 60_000),
  };
}

function merge(intervals: Interval[]): Interval[] {
  const sorted = intervals
    .filter((item) => item.endMinute > item.startMinute)
    .sort((a, b) => a.startMinute - b.startMinute);
  const result: Interval[] = [];
  for (const item of sorted) {
    const previous = result[result.length - 1];
    if (previous && item.startMinute <= previous.endMinute) {
      previous.endMinute = Math.max(previous.endMinute, item.endMinute);
    } else {
      result.push({ ...item });
    }
  }
  return result;
}

export class AvailabilityService {
  private readonly notifications: NotificationService;

  constructor(
    private readonly database: SqlDatabase,
  ) {
    this.notifications = new NotificationService(database);
  }

  private async requireFriendship(userId: string, friendId: string): Promise<Visibility> {
    const result = await this.database.execute<{ pair_key: string; visibility: Visibility }>({
      sql: `SELECT f.pair_key, u.schedule_visibility AS visibility
            FROM friendships f JOIN users u ON u.id = ?
            WHERE f.pair_key = ? AND u.status = 'active'`,
      params: [friendId, pairKey(userId, friendId)],
    });
    const row = result.rows[0];
    if (!row) throw new DomainError('friendship_required', '只能查询好友的共同空闲时间', 403);
    if (row.visibility === 'private') {
      throw new DomainError('schedule_private', '该好友未开放课表忙闲信息', 403);
    }
    return row.visibility;
  }

  /**
   * Shared free time for a friend. `freeSlots` are computed from both schedules.
   * `friendBlocks` reveals the friend's busy blocks according to their visibility:
   * busy_only → none; course_name → course names; full → course names and plan titles.
   * Notes are never returned.
   */
  async query(userId: string, input: {
    friendId: string;
    date: string;
    weekNumber: number;
    dayStartMinute: number;
    dayEndMinute: number;
    timezoneOffsetMinutes: number;
  }) {
    const visibility = await this.requireFriendship(userId, input.friendId);
    const localMidnightUtc = new Date(`${input.date}T00:00:00.000Z`);
    if (Number.isNaN(localMidnightUtc.getTime())) {
      throw new DomainError('invalid_date', '日期格式无效', 400);
    }
    const weekday = localMidnightUtc.getUTCDay() || 7;
    const dayStartUtc = new Date(
      localMidnightUtc.getTime() - input.timezoneOffsetMinutes * 60_000,
    );
    const dayEndUtc = new Date(dayStartUtc.getTime() + 86_400_000);
    const courseRows = await this.database.execute<CourseBusyRow>({
      sql: `SELECT c.user_id, c.name, m.start_minute, m.end_minute
            FROM courses c JOIN course_meetings m ON m.course_id = c.id
            WHERE c.user_id IN (?, ?) AND m.weekday = ?
              AND m.start_week <= ? AND m.end_week >= ?
              AND (m.week_parity = 'all'
                OR (m.week_parity = 'odd' AND ? % 2 = 1)
                OR (m.week_parity = 'even' AND ? % 2 = 0))`,
      params: [userId, input.friendId, weekday, input.weekNumber, input.weekNumber,
        input.weekNumber, input.weekNumber],
    });
    const planRows = await this.database.execute<PlanBusyRow>({
      sql: `SELECT user_id, title, starts_at, ends_at FROM plans
            WHERE user_id IN (?, ?) AND completed_at IS NULL
              AND starts_at < ? AND ends_at > ?`,
      params: [userId, input.friendId, dayEndUtc.toISOString(), dayStartUtc.toISOString()],
    });
    const blocks = [
      ...courseRows.rows.map((row) => ({
        userId: row.user_id,
        kind: 'course' as const,
        title: row.name,
        startMinute: row.start_minute,
        endMinute: row.end_minute,
      })),
      ...planRows.rows.map((row) => ({
        userId: row.user_id,
        kind: 'plan' as const,
        title: row.title,
        ...minutesWithin(row.starts_at, row.ends_at, dayStartUtc, dayEndUtc),
      })),
    ];

    const busy = merge(blocks.map(({ startMinute, endMinute }) => ({ startMinute, endMinute })))
      .map((item) => ({
        startMinute: Math.max(input.dayStartMinute, item.startMinute),
        endMinute: Math.min(input.dayEndMinute, item.endMinute),
      })).filter((item) => item.endMinute > item.startMinute);
    const free: Interval[] = [];
    let cursor = input.dayStartMinute;
    for (const item of busy) {
      if (item.startMinute > cursor) free.push({ startMinute: cursor, endMinute: item.startMinute });
      cursor = Math.max(cursor, item.endMinute);
    }
    if (cursor < input.dayEndMinute) {
      free.push({ startMinute: cursor, endMinute: input.dayEndMinute });
    }

    const friendBlocks = visibility === 'busy_only' ? [] : blocks
      .filter((block) => block.userId === input.friendId)
      .map((block) => ({
        startMinute: Math.max(input.dayStartMinute, block.startMinute),
        endMinute: Math.min(input.dayEndMinute, block.endMinute),
        kind: block.kind,
        title: block.kind === 'plan' && visibility === 'course_name' ? null : block.title,
      }))
      .filter((block) => block.endMinute > block.startMinute)
      .sort((a, b) => a.startMinute - b.startMinute);

    return { date: input.date, weekNumber: input.weekNumber, freeSlots: free, friendBlocks };
  }

  async createInvite(userId: string, input: {
    friendId: string; startsAt: string; endsAt: string; title: string;
  }) {
    await this.requireFriendship(userId, input.friendId);
    if (new Date(input.endsAt) <= new Date(input.startsAt)) {
      throw new DomainError('invalid_invite_time', '结束时间必须晚于开始时间', 400);
    }
    const id = crypto.randomUUID();
    await this.database.execute({
      sql: `INSERT INTO availability_invites
            (id, sender_id, receiver_id, starts_at, ends_at, title, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)`,
      params: [id, userId, input.friendId, input.startsAt, input.endsAt,
        input.title, new Date().toISOString()],
    });
    const sender = await this.database.execute<{ display_name: string }>({
      sql: 'SELECT display_name FROM users WHERE id = ?',
      params: [userId],
    });
    await this.notifications.create({
      recipientId: input.friendId,
      actorId: userId,
      kind: 'availability_invite',
      title: '收到共同空闲邀请',
      body: `${sender.rows[0]?.display_name ?? '一位好友'}邀请你：${input.title}`,
      targetPath: '/discover/availability',
    });
    return { id };
  }

  async respond(userId: string, inviteId: string, action: 'accept' | 'reject' | 'cancel') {
    const result = await this.database.execute<InviteRow>({
      sql: `SELECT id, sender_id, receiver_id, starts_at, ends_at, title, status, created_at
            FROM availability_invites WHERE id = ?`,
      params: [inviteId],
    });
    const invite = result.rows[0];
    if (!invite || invite.status !== 'pending') {
      throw new DomainError('invite_not_found', '邀请不存在或已处理', 404);
    }
    if (action === 'cancel' ? invite.sender_id !== userId : invite.receiver_id !== userId) {
      throw new DomainError('invite_forbidden', '无权处理该邀请', 403);
    }
    const status = action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : 'canceled';
    await this.database.execute({
      sql: 'UPDATE availability_invites SET status = ?, responded_at = ? WHERE id = ?',
      params: [status, new Date().toISOString(), inviteId],
    });
  }

  async listInvites(userId: string) {
    const result = await this.database.execute<InviteListRow>({
      sql: `SELECT i.id, i.sender_id, i.receiver_id, i.starts_at, i.ends_at,
                   i.title, i.status, i.created_at,
                   u.id AS other_user_id, u.display_name
            FROM availability_invites i
            JOIN users u ON u.id = CASE WHEN i.sender_id = ? THEN i.receiver_id ELSE i.sender_id END
            WHERE i.sender_id = ? OR i.receiver_id = ?
            ORDER BY i.starts_at DESC`,
      params: [userId, userId, userId],
    });
    return result.rows.map((row) => ({
      id: row.id,
      direction: row.sender_id === userId ? 'outgoing' : 'incoming',
      userId: row.other_user_id,
      displayName: row.display_name,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      title: row.title,
      status: row.status,
      createdAt: row.created_at,
    }));
  }
}
