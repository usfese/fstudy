import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

export type MeetingInput = {
  weekday: number;
  startMinute: number;
  endMinute: number;
  startWeek: number;
  endWeek: number;
  weekParity: 'all' | 'odd' | 'even';
  campus: string | null;
  building: string | null;
  room: string | null;
};

export type CourseInput = {
  name: string;
  teacher: string | null;
  color: string;
  meetings: MeetingInput[];
};

type CourseRow = {
  id: string;
  name: string;
  teacher: string | null;
  color: string;
  meeting_id: string | null;
  weekday: number | null;
  start_minute: number | null;
  end_minute: number | null;
  start_week: number | null;
  end_week: number | null;
  week_parity: MeetingInput['weekParity'] | null;
  campus: string | null;
  building: string | null;
  room: string | null;
};

export class ScheduleService {
  constructor(private readonly database: SqlDatabase) {}

  async createCourse(userId: string, input: CourseInput) {
    if (input.meetings.length === 0) throw new DomainError('meeting_required', '课程至少需要一个上课时间');
    const courseId = crypto.randomUUID();
    await this.database.batch([
      {
        sql: 'INSERT INTO courses (id, user_id, name, teacher, color, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        params: [courseId, userId, input.name, input.teacher, input.color, new Date().toISOString()],
      },
      ...this.meetingStatements(courseId, input.meetings),
    ]);
    return { id: courseId };
  }

  async updateCourse(userId: string, courseId: string, input: CourseInput) {
    if (input.meetings.length === 0) throw new DomainError('meeting_required', '课程至少需要一个上课时间');
    const existing = await this.database.execute<{ id: string }>({
      sql: 'SELECT id FROM courses WHERE id = ? AND user_id = ?',
      params: [courseId, userId],
    });
    if (existing.rows.length === 0) {
      throw new DomainError('course_not_found', '课程不存在', 404);
    }
    await this.database.batch([
      {
        sql: 'UPDATE courses SET name = ?, teacher = ?, color = ? WHERE id = ? AND user_id = ?',
        params: [input.name, input.teacher, input.color, courseId, userId],
      },
      { sql: 'DELETE FROM course_meetings WHERE course_id = ?', params: [courseId] },
      ...this.meetingStatements(courseId, input.meetings),
    ]);
  }

  async deleteCourse(userId: string, courseId: string) {
    const result = await this.database.execute({
      sql: 'DELETE FROM courses WHERE id = ? AND user_id = ?',
      params: [courseId, userId],
    });
    if (result.changes === 0) {
      throw new DomainError('course_not_found', '课程不存在', 404);
    }
  }

  async clearCourses(userId: string) {
    await this.database.execute({
      sql: 'DELETE FROM courses WHERE user_id = ?',
      params: [userId],
    });
  }

  private meetingStatements(courseId: string, meetings: MeetingInput[]) {
    return meetings.map((meeting) => ({
      sql: `INSERT INTO course_meetings
        (id, course_id, weekday, start_minute, end_minute, start_week, end_week, week_parity, campus, building, room)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      params: [
        crypto.randomUUID(), courseId, meeting.weekday, meeting.startMinute, meeting.endMinute,
        meeting.startWeek, meeting.endWeek, meeting.weekParity, meeting.campus, meeting.building, meeting.room,
      ],
    }));
  }

  async listCourses(userId: string) {
    const result = await this.database.execute<CourseRow>({
      sql: `SELECT c.id, c.name, c.teacher, c.color, m.id AS meeting_id, m.weekday,
                   m.start_minute, m.end_minute, m.start_week, m.end_week, m.week_parity,
                   m.campus, m.building, m.room
            FROM courses c LEFT JOIN course_meetings m ON m.course_id = c.id
            WHERE c.user_id = ? ORDER BY m.weekday, m.start_minute`,
      params: [userId],
    });
    const courses = new Map<string, { id: string; name: string; teacher: string | null; color: string; meetings: object[] }>();
    for (const row of result.rows) {
      const course = courses.get(row.id) ?? {
        id: row.id, name: row.name, teacher: row.teacher, color: row.color, meetings: [],
      };
      if (row.meeting_id !== null) {
        course.meetings.push({
          id: row.meeting_id, weekday: row.weekday, startMinute: row.start_minute,
          endMinute: row.end_minute, startWeek: row.start_week, endWeek: row.end_week,
          weekParity: row.week_parity, campus: row.campus, building: row.building, room: row.room,
        });
      }
      courses.set(row.id, course);
    }
    return [...courses.values()];
  }
}
