import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

type PlanRow = {
  id: string;
  title: string;
  notes: string;
  starts_at: string;
  ends_at: string;
  reminder_minutes: number | null;
  completed_at: string | null;
  created_at: string;
};

export class PlanService {
  constructor(private readonly database: SqlDatabase) {}

  async list(userId: string) {
    const result = await this.database.execute<PlanRow>({
      sql: `SELECT id, title, notes, starts_at, ends_at, reminder_minutes, completed_at, created_at
            FROM plans WHERE user_id = ?
            ORDER BY completed_at IS NOT NULL, starts_at`,
      params: [userId],
    });
    return result.rows.map((row) => ({
      id: row.id,
      title: row.title,
      notes: row.notes,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      reminderMinutes: row.reminder_minutes,
      completedAt: row.completed_at,
      createdAt: row.created_at,
    }));
  }

  async create(
    userId: string,
    input: {
      title: string;
      notes: string;
      startsAt: string;
      endsAt: string;
      reminderMinutes: number | null;
    },
  ) {
    if (new Date(input.endsAt) <= new Date(input.startsAt)) {
      throw new DomainError('invalid_plan_time', '结束时间必须晚于开始时间', 400);
    }
    const id = crypto.randomUUID();
    await this.database.execute({
      sql: `INSERT INTO plans
            (id, user_id, title, notes, starts_at, ends_at, reminder_minutes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      params: [
        id,
        userId,
        input.title,
        input.notes,
        input.startsAt,
        input.endsAt,
        input.reminderMinutes,
        new Date().toISOString(),
      ],
    });
    return { id };
  }

  async setCompleted(userId: string, planId: string, completed: boolean) {
    const result = await this.database.execute({
      sql: 'UPDATE plans SET completed_at = ? WHERE id = ? AND user_id = ?',
      params: [completed ? new Date().toISOString() : null, planId, userId],
    });
    if (result.changes === 0) {
      throw new DomainError('plan_not_found', '安排不存在', 404);
    }
  }
}
