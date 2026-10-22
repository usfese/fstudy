import type { SqlDatabase } from '../../core/types.js';
import { DomainError } from '../../core/errors.js';

type AssignmentRow = {
  id: string;
  course_id: string | null;
  title: string;
  notes: string;
  due_at: string | null;
  completed_at: string | null;
  created_at: string;
};

export class AssignmentService {
  constructor(private readonly database: SqlDatabase) {}

  async create(
    userId: string,
    input: { courseId: string | null; title: string; notes: string; dueAt: string | null },
  ) {
    if (input.courseId !== null) {
      const course = await this.database.execute<{ id: string }>({
        sql: 'SELECT id FROM courses WHERE id = ? AND user_id = ?',
        params: [input.courseId, userId],
      });
      if (course.rows.length === 0) {
        throw new DomainError('course_not_found', '课程不存在', 404);
      }
    }
    const id = crypto.randomUUID();
    await this.database.execute({
      sql: `INSERT INTO assignments (id, user_id, course_id, title, notes, due_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)`,
      params: [id, userId, input.courseId, input.title, input.notes, input.dueAt, new Date().toISOString()],
    });
    return { id };
  }

  async update(
    userId: string,
    assignmentId: string,
    input: { courseId: string | null; title: string; notes: string; dueAt: string | null },
  ) {
    if (input.courseId !== null) {
      const course = await this.database.execute<{ id: string }>({
        sql: 'SELECT id FROM courses WHERE id = ? AND user_id = ?',
        params: [input.courseId, userId],
      });
      if (course.rows.length === 0) {
        throw new DomainError('course_not_found', '课程不存在', 404);
      }
    }
    const result = await this.database.execute({
      sql: `UPDATE assignments SET course_id = ?, title = ?, notes = ?, due_at = ?
            WHERE id = ? AND user_id = ?`,
      params: [input.courseId, input.title, input.notes, input.dueAt, assignmentId, userId],
    });
    if (result.changes === 0) {
      throw new DomainError('assignment_not_found', '作业不存在', 404);
    }
  }

  async delete(userId: string, assignmentId: string) {
    const result = await this.database.execute({
      sql: 'DELETE FROM assignments WHERE id = ? AND user_id = ?',
      params: [assignmentId, userId],
    });
    if (result.changes === 0) {
      throw new DomainError('assignment_not_found', '作业不存在', 404);
    }
  }

  async list(userId: string) {
    const result = await this.database.execute<AssignmentRow>({
      sql: `SELECT id, course_id, title, notes, due_at, completed_at, created_at
            FROM assignments WHERE user_id = ? ORDER BY completed_at IS NOT NULL, due_at IS NULL, due_at`,
      params: [userId],
    });
    return result.rows.map((row) => ({
      id: row.id,
      courseId: row.course_id,
      title: row.title,
      notes: row.notes,
      dueAt: row.due_at,
      completedAt: row.completed_at,
      createdAt: row.created_at,
    }));
  }

  async setCompleted(userId: string, assignmentId: string, completed: boolean): Promise<boolean> {
    const result = await this.database.execute({
      sql: 'UPDATE assignments SET completed_at = ? WHERE id = ? AND user_id = ?',
      params: [completed ? new Date().toISOString() : null, assignmentId, userId],
    });
    return result.changes > 0;
  }
}
