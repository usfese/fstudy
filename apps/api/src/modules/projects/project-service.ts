import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

type ProjectRow = {
  id: string; owner_id: string; owner_name: string; title: string; description: string;
  status: 'recruiting' | 'in_progress' | 'closed'; capacity: number;
  created_at: string; updated_at: string; member_count: number;
  my_application_status: string | null;
};
type ProjectTagRow = { project_id: string; id: string; category: string; name: string };
type ApplicationRow = {
  id: string; project_id: string; project_title: string; applicant_id: string;
  applicant_name: string; message: string; status: string; created_at: string;
  owner_id: string;
};

export class ProjectService {
  constructor(private readonly database: SqlDatabase) {}

  async list(userId: string, status?: string, tagId?: string) {
    const conditions = ['1 = 1'];
    const params: Array<string | number | null> = [userId];
    if (status) {
      conditions.push('p.status = ?');
      params.push(status);
    }
    if (tagId) {
      conditions.push('EXISTS (SELECT 1 FROM project_tags filter_tag WHERE filter_tag.project_id = p.id AND filter_tag.tag_id = ?)');
      params.push(tagId);
    }
    const projects = await this.database.execute<ProjectRow>({
      sql: `SELECT p.id, p.owner_id, u.display_name AS owner_name, p.title, p.description,
                   p.status, p.capacity, p.created_at, p.updated_at,
                   (SELECT COUNT(*) FROM project_members pm WHERE pm.project_id = p.id) AS member_count,
                   (SELECT pa.status FROM project_applications pa
                    WHERE pa.project_id = p.id AND pa.applicant_id = ?) AS my_application_status
             FROM projects p JOIN users u ON u.id = p.owner_id
             WHERE ${conditions.length ? `${conditions.join(' AND ')} AND ` : ''}p.moderation_status = 'visible'
            ORDER BY CASE p.status WHEN 'recruiting' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END,
                     p.updated_at DESC
            LIMIT 100`,
      params,
    });
    if (projects.rows.length === 0) return [];
    const placeholders = projects.rows.map(() => '?').join(',');
    const tags = await this.database.execute<ProjectTagRow>({
      sql: `SELECT pt.project_id, t.id, t.category, t.name
            FROM project_tags pt JOIN tags t ON t.id = pt.tag_id
            WHERE pt.project_id IN (${placeholders}) ORDER BY t.category, t.name`,
      params: projects.rows.map((project) => project.id),
    });
    return projects.rows.map((project) => ({
      id: project.id,
      ownerId: project.owner_id,
      ownerName: project.owner_name,
      title: project.title,
      description: project.description,
      status: project.status,
      capacity: project.capacity,
      memberCount: project.member_count,
      createdAt: project.created_at,
      updatedAt: project.updated_at,
      ownedByMe: project.owner_id === userId,
      myApplicationStatus: project.my_application_status,
      tags: tags.rows.filter((tag) => tag.project_id === project.id).map((tag) => ({
        id: tag.id, category: tag.category, name: tag.name,
      })),
    }));
  }

  async create(userId: string, input: {
    title: string; description: string; capacity: number; tagIds: string[];
  }) {
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const recent = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM projects WHERE owner_id = ? AND created_at >= ?',
      params: [userId, since],
    });
    if ((recent.rows[0]?.count ?? 0) >= 5) {
      throw new DomainError('project_publish_rate_limited', '每天最多发布 5 个项目', 429);
    }
    await this.validateTags(input.tagIds);
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    await this.database.batch([
      {
        sql: `INSERT INTO projects
              (id, owner_id, title, description, status, capacity, created_at, updated_at)
              VALUES (?, ?, ?, ?, 'recruiting', ?, ?, ?)`,
        params: [id, userId, input.title, input.description, input.capacity, now, now],
      },
      {
        sql: 'INSERT INTO project_members (project_id, user_id, joined_at) VALUES (?, ?, ?)',
        params: [id, userId, now],
      },
      ...input.tagIds.map((tagId) => ({
        sql: 'INSERT INTO project_tags (project_id, tag_id) VALUES (?, ?)',
        params: [id, tagId],
      })),
    ]);
    return { id };
  }

  private async validateTags(tagIds: string[]) {
    if (new Set(tagIds).size !== tagIds.length) {
      throw new DomainError('duplicate_tags', '项目标签不能重复');
    }
    if (tagIds.length === 0) return;
    const placeholders = tagIds.map(() => '?').join(',');
    const tags = await this.database.execute<{ id: string }>({
      sql: `SELECT id FROM tags WHERE id IN (${placeholders}) AND active = 1
            AND category IN ('field', 'goal')`,
      params: tagIds,
    });
    if (tags.rows.length !== tagIds.length) {
      throw new DomainError('invalid_project_tag', '项目只能使用有效的领域或目标标签');
    }
  }

  async setStatus(userId: string, projectId: string, status: 'recruiting' | 'in_progress' | 'closed') {
    const result = await this.database.execute({
      sql: 'UPDATE projects SET status = ?, updated_at = ? WHERE id = ? AND owner_id = ?',
      params: [status, new Date().toISOString(), projectId, userId],
    });
    if (result.changes === 0) throw new DomainError('project_not_found', '项目不存在或无权修改', 404);
  }

  async apply(userId: string, projectId: string, message: string) {
    const project = await this.database.execute<{ owner_id: string; status: string; capacity: number; member_count: number }>({
      sql: `SELECT p.owner_id, p.status, p.capacity,
              (SELECT COUNT(*) FROM project_members pm WHERE pm.project_id = p.id) AS member_count
            FROM projects p WHERE p.id = ?`,
      params: [projectId],
    });
    const row = project.rows[0];
    if (!row) throw new DomainError('project_not_found', '项目不存在', 404);
    if (row.owner_id === userId) throw new DomainError('cannot_apply_own_project', '不能申请自己创建的项目');
    if (row.status !== 'recruiting') throw new DomainError('project_not_recruiting', '项目当前未开放申请', 409);
    if (row.member_count >= row.capacity) throw new DomainError('project_full', '项目成员已满', 409);
    const since = new Date(Date.now() - 3_600_000).toISOString();
    const recent = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM project_applications WHERE applicant_id = ? AND created_at >= ?',
      params: [userId, since],
    });
    if ((recent.rows[0]?.count ?? 0) >= 10) {
      throw new DomainError('project_application_rate_limited', '每小时最多申请 10 个项目', 429);
    }
    const id = crypto.randomUUID();
    try {
      await this.database.execute({
        sql: `INSERT INTO project_applications
              (id, project_id, applicant_id, message, status, created_at)
              VALUES (?, ?, ?, ?, 'pending', ?)`,
        params: [id, projectId, userId, message, new Date().toISOString()],
      });
    } catch (error) {
      if (String(error).toLowerCase().includes('unique')) {
        throw new DomainError('application_already_exists', '已经申请过该项目', 409);
      }
      throw error;
    }
    return { id };
  }

  async listApplications(userId: string) {
    const result = await this.database.execute<ApplicationRow>({
      sql: `SELECT pa.id, pa.project_id, p.title AS project_title, pa.applicant_id,
                   u.display_name AS applicant_name, pa.message, pa.status,
                   pa.created_at, p.owner_id
            FROM project_applications pa
            JOIN projects p ON p.id = pa.project_id
            JOIN users u ON u.id = pa.applicant_id
            WHERE pa.applicant_id = ? OR p.owner_id = ?
            ORDER BY pa.created_at DESC`,
      params: [userId, userId],
    });
    return result.rows.map((row) => ({
      id: row.id,
      projectId: row.project_id,
      projectTitle: row.project_title,
      applicantId: row.applicant_id,
      applicantName: row.applicant_name,
      message: row.message,
      status: row.status,
      createdAt: row.created_at,
      direction: row.owner_id === userId ? 'incoming' : 'outgoing',
    }));
  }

  async respond(userId: string, applicationId: string, action: 'accept' | 'reject' | 'withdraw') {
    const result = await this.database.execute<ApplicationRow & { capacity: number; member_count: number; project_status: string }>({
      sql: `SELECT pa.id, pa.project_id, p.title AS project_title, pa.applicant_id,
                   u.display_name AS applicant_name, pa.message, pa.status, pa.created_at,
                   p.owner_id, p.capacity, p.status AS project_status,
                   (SELECT COUNT(*) FROM project_members pm WHERE pm.project_id = p.id) AS member_count
            FROM project_applications pa JOIN projects p ON p.id = pa.project_id
            JOIN users u ON u.id = pa.applicant_id WHERE pa.id = ?`,
      params: [applicationId],
    });
    const application = result.rows[0];
    if (!application || application.status !== 'pending') {
      throw new DomainError('application_not_found', '申请不存在或已处理', 404);
    }
    if (action === 'withdraw' ? application.applicant_id !== userId : application.owner_id !== userId) {
      throw new DomainError('application_forbidden', '无权处理该申请', 403);
    }
    if (action === 'accept' && (application.project_status !== 'recruiting' || application.member_count >= application.capacity)) {
      throw new DomainError('project_not_available', '项目未招募或成员已满', 409);
    }
    const now = new Date().toISOString();
    if (action === 'accept') {
      await this.database.batch([
        {
          sql: `INSERT INTO project_members (project_id, user_id, joined_at)
                SELECT p.id, pa.applicant_id, ?
                FROM project_applications pa JOIN projects p ON p.id = pa.project_id
                WHERE pa.id = ? AND pa.status = 'pending' AND p.status = 'recruiting'
                  AND (SELECT COUNT(*) FROM project_members pm WHERE pm.project_id = p.id) < p.capacity`,
          params: [now, applicationId],
        },
        {
          sql: `UPDATE project_applications SET status = 'accepted', responded_at = ?
                WHERE id = ? AND status = 'pending'
                  AND EXISTS (
                    SELECT 1 FROM project_members pm
                    WHERE pm.project_id = project_applications.project_id
                      AND pm.user_id = project_applications.applicant_id
                  )`,
          params: [now, applicationId],
        },
      ]);
      const accepted = await this.database.execute<{ status: string }>({
        sql: 'SELECT status FROM project_applications WHERE id = ?',
        params: [applicationId],
      });
      if (accepted.rows[0]?.status !== 'accepted') {
        throw new DomainError('project_not_available', '项目未招募或成员已满', 409);
      }
      return;
    }
    const status = action === 'reject' ? 'rejected' : 'withdrawn';
    const updated = await this.database.execute({
      sql: `UPDATE project_applications SET status = ?, responded_at = ?
            WHERE id = ? AND status = 'pending'`,
      params: [status, now, applicationId],
    });
    if (updated.changes === 0) {
      throw new DomainError('application_not_found', '申请不存在或已处理', 404);
    }
  }
}
