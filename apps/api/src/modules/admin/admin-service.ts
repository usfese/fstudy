import { DomainError } from '../../core/errors.js';
import { createOpaqueToken, createPasswordCredential, hashToken, verifyPassword } from '../../core/security.js';
import type { RuntimeDependencies, SqlDatabase } from '../../core/types.js';

const SESSION_DAYS = 8;
const LOGIN_WINDOW_MS = 15 * 60_000;
const MAX_FAILURES = 5;
const DUMMY_CREDENTIAL = {
  hash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  iterations: 100_000,
};

type AdminCredential = {
  password_hash: string;
  password_salt: string;
  password_iterations: number;
};

export class AdminService {
  constructor(private readonly dependencies: RuntimeDependencies) {}

  private get database(): SqlDatabase { return this.dependencies.database; }
  private now(): Date { return (this.dependencies.clock ?? (() => new Date()))(); }

  async bootstrap(): Promise<void> {
    const username = this.dependencies.adminBootstrapUsername?.trim();
    const password = this.dependencies.adminBootstrapPassword;
    if (!username && !password) return;
    const existing = await this.database.execute<{ username: string }>({
      sql: 'SELECT username FROM admin_accounts LIMIT 1',
    });
    if (existing.rows.length) return;
    if (!username || !password || username.length < 3 || username.length > 64 || password.length < 14) {
      throw new Error('ADMIN_BOOTSTRAP_USERNAME and a 14+ character ADMIN_BOOTSTRAP_PASSWORD are required');
    }
    const credential = await createPasswordCredential(password);
    await this.database.execute({
      sql: `INSERT INTO admin_accounts
        (username, password_hash, password_salt, password_iterations, created_at)
        VALUES (?, ?, ?, ?, ?)`,
      params: [username, credential.hash, credential.salt, credential.iterations, this.now().toISOString()],
    });
  }

  async login(usernameInput: string, password: string) {
    const username = usernameInput.trim();
    const key = username.toLowerCase();
    const now = this.now();
    const throttle = await this.database.execute<{ blocked_until: string | null }>({
      sql: 'SELECT blocked_until FROM admin_login_throttles WHERE username_key = ?',
      params: [key],
    });
    if (throttle.rows[0]?.blocked_until && new Date(throttle.rows[0].blocked_until!) > now) {
      throw new DomainError('admin_rate_limited', '登录尝试过多，请稍后再试', 429);
    }
    const result = await this.database.execute<AdminCredential>({
      sql: `SELECT password_hash, password_salt, password_iterations
            FROM admin_accounts WHERE username = ?`,
      params: [username],
    });
    const row = result.rows[0];
    const valid = await verifyPassword(password, row ? {
      hash: row.password_hash,
      salt: row.password_salt,
      iterations: row.password_iterations,
    } : DUMMY_CREDENTIAL);
    if (!row || !valid) {
      const current = await this.database.execute<{ failure_count: number; window_started_at: string }>({
        sql: 'SELECT failure_count, window_started_at FROM admin_login_throttles WHERE username_key = ?',
        params: [key],
      });
      const prior = current.rows[0];
      const inWindow = prior && now.getTime() - new Date(prior.window_started_at).getTime() < LOGIN_WINDOW_MS;
      const failures = inWindow ? prior.failure_count + 1 : 1;
      const windowStart = inWindow ? prior.window_started_at : now.toISOString();
      const blockedUntil = failures >= MAX_FAILURES ? new Date(now.getTime() + LOGIN_WINDOW_MS).toISOString() : null;
      await this.database.execute({
        sql: `INSERT INTO admin_login_throttles
          (username_key, failure_count, window_started_at, blocked_until, updated_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(username_key) DO UPDATE SET failure_count=excluded.failure_count,
            window_started_at=excluded.window_started_at, blocked_until=excluded.blocked_until,
            updated_at=excluded.updated_at`,
        params: [key, failures, windowStart, blockedUntil, now.toISOString()],
      });
      throw new DomainError('invalid_admin_credentials', '管理员账号或密码错误', 401);
    }
    await this.database.execute({
      sql: 'DELETE FROM admin_login_throttles WHERE username_key = ?', params: [key],
    });
    const token = createOpaqueToken();
    const expiresAt = new Date(now.getTime() + SESSION_DAYS * 86_400_000).toISOString();
    await this.database.batch([
      {
        sql: `INSERT INTO admin_sessions (id, username, token_hash, expires_at, created_at)
          VALUES (?, ?, ?, ?, ?)`,
        params: [crypto.randomUUID(), username, await hashToken(token), expiresAt, now.toISOString()],
      },
      { sql: 'UPDATE admin_accounts SET last_login_at = ? WHERE username = ?', params: [now.toISOString(), username] },
    ]);
    return { accessToken: token, expiresAt, username };
  }

  async authenticate(token: string | null): Promise<string> {
    if (!token) throw new DomainError('admin_authentication_required', '需要管理员登录', 401);
    const result = await this.database.execute<{ username: string }>({
      sql: `SELECT username FROM admin_sessions
        WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
      params: [await hashToken(token), this.now().toISOString()],
    });
    if (!result.rows[0]) throw new DomainError('invalid_admin_session', '管理员登录已失效', 401);
    return result.rows[0].username;
  }

  async logout(token: string): Promise<void> {
    await this.database.execute({
      sql: 'UPDATE admin_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL',
      params: [this.now().toISOString(), await hashToken(token)],
    });
  }

  async changePassword(username: string, currentPassword: string, newPassword: string): Promise<void> {
    if (newPassword.length < 14 || newPassword.length > 128) {
      throw new DomainError('invalid_admin_password', '新管理员密码至少 14 位且最多 128 位');
    }
    const result = await this.database.execute<AdminCredential>({
      sql: 'SELECT password_hash, password_salt, password_iterations FROM admin_accounts WHERE username = ?',
      params: [username],
    });
    const row = result.rows[0];
    if (!row || !(await verifyPassword(currentPassword, {
      hash: row.password_hash, salt: row.password_salt, iterations: row.password_iterations,
    }))) {
      throw new DomainError('invalid_admin_credentials', '当前管理员密码错误', 401);
    }
    const credential = await createPasswordCredential(newPassword);
    const now = this.now().toISOString();
    await this.database.batch([
      {
        sql: `UPDATE admin_accounts SET password_hash = ?, password_salt = ?, password_iterations = ? WHERE username = ?`,
        params: [credential.hash, credential.salt, credential.iterations, username],
      },
      { sql: 'UPDATE admin_sessions SET revoked_at = ? WHERE username = ? AND revoked_at IS NULL', params: [now, username] },
      {
        sql: 'INSERT INTO admin_audit_log (id, actor, action, entity_type, entity_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        params: [crypto.randomUUID(), username, 'admin.password_change', 'admin', username, '{}', now],
      },
    ]);
  }

  async overview() {
    const [users, activeUsers, posts, replies, projects, openReports, tags, todayUsers] = await Promise.all([
      this.count('users'), this.countWhere('users', "status = 'active'"), this.count('forum_posts'),
      this.count('forum_replies'), this.count('projects'), this.countWhere('content_reports', "status = 'open'"),
      this.countWhere('tags', 'active = 1'),
      this.countSince('users', 'created_at'),
    ]);
    const [todayPosts, todayProjects] = await Promise.all([
      this.countSince('forum_posts', 'created_at'), this.countSince('projects', 'created_at'),
    ]);
    return { users, activeUsers, posts, replies, projects, openReports, tags, todayUsers, todayPosts, todayProjects };
  }

  async createReport(reporterId: string, input: { targetType: string; targetId: string; reason: string }) {
    const existenceSql: Record<string, string> = {
      forum_post: 'SELECT id FROM forum_posts WHERE id = ?',
      forum_reply: 'SELECT id FROM forum_replies WHERE id = ?',
      project: 'SELECT id FROM projects WHERE id = ?',
    };
    const existenceQuery = existenceSql[input.targetType];
    if (!existenceQuery) throw new DomainError('invalid_report_target', '举报内容类型无效');
    const target = await this.database.execute({
      sql: existenceQuery, params: [input.targetId],
    });
    if (!target.rows.length) throw new DomainError('report_target_not_found', '举报内容不存在', 404);
    const prior = await this.database.execute({
      sql: "SELECT id FROM content_reports WHERE reporter_id = ? AND target_type = ? AND target_id = ? AND status = 'open'",
      params: [reporterId, input.targetType, input.targetId],
    });
    if (prior.rows.length) throw new DomainError('duplicate_report', '你已举报过该内容', 409);
    const since = new Date(this.now().getTime() - 86_400_000).toISOString();
    const recent = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM content_reports WHERE reporter_id = ? AND created_at >= ?',
      params: [reporterId, since],
    });
    if ((recent.rows[0]?.count ?? 0) >= 10) throw new DomainError('report_rate_limited', '每天最多提交 10 次举报', 429);
    const id = crypto.randomUUID();
    await this.database.execute({
      sql: 'INSERT INTO content_reports (id, reporter_id, target_type, target_id, reason, status, created_at) VALUES (?, ?, ?, ?, ?, \'open\', ?)',
      params: [id, reporterId, input.targetType, input.targetId, input.reason, this.now().toISOString()],
    });
    return { id };
  }

  private async count(table: string): Promise<number> {
    const result = await this.database.execute<{ count: number }>({ sql: `SELECT COUNT(*) AS count FROM ${table}` });
    return result.rows[0]?.count ?? 0;
  }

  private async countWhere(table: string, where: string): Promise<number> {
    const result = await this.database.execute<{ count: number }>({ sql: `SELECT COUNT(*) AS count FROM ${table} WHERE ${where}` });
    return result.rows[0]?.count ?? 0;
  }

  private async countSince(table: string, column: string): Promise<number> {
    const since = new Date(this.now().getTime() - 86_400_000).toISOString();
    const result = await this.database.execute<{ count: number }>({
      sql: `SELECT COUNT(*) AS count FROM ${table} WHERE ${column} >= ?`, params: [since],
    });
    return result.rows[0]?.count ?? 0;
  }

  async listUsers(query = '') {
    const term = `%${query.trim().slice(0, 80)}%`;
    const result = await this.database.execute({
      sql: `SELECT u.id, u.display_name AS displayName, u.department_id AS departmentId,
        u.status, u.created_at AS createdAt, i.verified_at AS verifiedAt,
        (SELECT COUNT(*) FROM forum_posts p WHERE p.author_id=u.id) AS postCount,
        (SELECT COUNT(*) FROM projects p WHERE p.owner_id=u.id) AS projectCount
        FROM users u JOIN student_identities i ON i.user_id=u.id
        WHERE u.display_name LIKE ? OR u.id = ? ORDER BY u.created_at DESC LIMIT 100`,
      params: [term, query.trim()],
    });
    return result.rows;
  }

  async setUserStatus(actor: string, userId: string, status: 'active' | 'suspended') {
    const updated = await this.database.execute({
      sql: "UPDATE users SET status = ?, discoverable = CASE WHEN ? = 'suspended' THEN 0 ELSE discoverable END WHERE id = ?",
      params: [status, status, userId],
    });
    if (!updated.changes) throw new DomainError('user_not_found', '用户不存在', 404);
    if (status === 'suspended') {
      await this.database.execute({
        sql: 'UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
        params: [this.now().toISOString(), userId],
      });
    }
    await this.audit(actor, `user.${status}`, 'user', userId, {});
  }

  async listContent() {
    const [posts, replies, projects] = await Promise.all([
      this.database.execute({ sql: `SELECT p.id, p.title || char(10) || p.body AS content, p.category AS kind,
        'forum_post' AS contentType, p.moderation_status AS moderationStatus, p.created_at AS createdAt,
        u.display_name AS authorName FROM forum_posts p JOIN users u ON u.id=p.author_id
        ORDER BY p.created_at DESC LIMIT 100` }),
      this.database.execute({ sql: `SELECT r.id, substr(r.body, 1, 300) AS content, 'reply' AS kind,
        'forum_reply' AS contentType, r.moderation_status AS moderationStatus, r.created_at AS createdAt,
        u.display_name AS authorName FROM forum_replies r JOIN users u ON u.id=r.author_id
        ORDER BY r.created_at DESC LIMIT 100` }),
      this.database.execute({ sql: `SELECT p.id, p.title AS content, p.status AS kind,
        'project' AS contentType, p.moderation_status AS moderationStatus, p.created_at AS createdAt,
        u.display_name AS authorName FROM projects p JOIN users u ON u.id=p.owner_id
        ORDER BY p.created_at DESC LIMIT 100` }),
    ]);
    return [...posts.rows, ...replies.rows, ...projects.rows].sort((first, second) =>
      String(second.createdAt).localeCompare(String(first.createdAt)));
  }

  async moderateContent(actor: string, type: string, id: string, action: 'hide' | 'restore' | 'delete') {
    const mapping: Record<string, { table: string; field: string }> = {
      forum_post: { table: 'forum_posts', field: 'moderation_status' },
      forum_reply: { table: 'forum_replies', field: 'moderation_status' },
      project: { table: 'projects', field: 'moderation_status' },
    };
    const target = mapping[type];
    if (!target) throw new DomainError('invalid_content_type', '内容类型无效');
    let statement: string;
    let params: (string | null)[];
    if (action === 'delete') {
      statement = `DELETE FROM ${target.table} WHERE id = ?`;
      params = [id];
    } else if (type === 'project') {
      statement = 'UPDATE projects SET moderation_status = ? WHERE id = ?';
      params = [action === 'hide' ? 'hidden' : 'visible', id];
    } else {
      statement = `UPDATE ${target.table} SET moderation_status = ? WHERE id = ?`;
      params = [action === 'hide' ? 'hidden' : 'visible', id];
    }
    const result = await this.database.execute({ sql: statement, params });
    if (!result.changes) throw new DomainError('content_not_found', '内容不存在', 404);
    await this.audit(actor, `content.${action}`, type, id, {});
  }

  async listReports() {
    const result = await this.database.execute({
      sql: `SELECT r.id, r.reporter_id AS reporterId, reporter.display_name AS reporterName,
        r.target_type AS targetType, r.target_id AS targetId, r.reason, r.status,
        r.created_at AS createdAt, r.reviewed_at AS reviewedAt, r.reviewed_by AS reviewedBy,
        CASE r.target_type
          WHEN 'forum_post' THEN (SELECT fp.title || char(10) || fp.body FROM forum_posts fp WHERE fp.id=r.target_id)
          WHEN 'forum_reply' THEN (SELECT fr.body FROM forum_replies fr WHERE fr.id=r.target_id)
          WHEN 'project' THEN (SELECT p.title || char(10) || p.description FROM projects p WHERE p.id=r.target_id)
          ELSE NULL END AS targetContent
        FROM content_reports r JOIN users reporter ON reporter.id=r.reporter_id
        ORDER BY CASE r.status WHEN 'open' THEN 0 ELSE 1 END, r.created_at DESC, r.id DESC LIMIT 200`,
    });
    return result.rows;
  }

  async updateReport(actor: string, id: string, status: 'resolved' | 'dismissed') {
    const now = this.now().toISOString();
    const result = await this.database.execute({
      sql: "UPDATE content_reports SET status = ?, reviewed_at = ?, reviewed_by = ? WHERE id = ? AND status = 'open'",
      params: [status, now, actor, id],
    });
    if (!result.changes) throw new DomainError('report_not_found', '待处理举报不存在', 404);
    await this.audit(actor, `report.${status}`, 'report', id, {});
  }

  async listTags() {
    const result = await this.database.execute({
      sql: 'SELECT id, category, name, active FROM tags ORDER BY category, name',
    });
    return result.rows;
  }

  async saveTag(actor: string, input: { id?: string | undefined; category: string; name: string; active: boolean }) {
    const id = input.id?.trim() || `${input.category}-${crypto.randomUUID()}`;
    if (!['interest', 'field', 'goal'].includes(input.category)) throw new DomainError('invalid_tag_category', '标签分类无效');
    const name = input.name.trim();
    if (!name || name.length > 40) throw new DomainError('invalid_tag_name', '标签名称需为 1–40 个字符');
    try {
      await this.database.execute({
        sql: `INSERT INTO tags (id, category, name, active) VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET category=excluded.category, name=excluded.name, active=excluded.active`,
        params: [id, input.category, name, input.active ? 1 : 0],
      });
    } catch {
      throw new DomainError('duplicate_tag', '同分类下已存在此标签', 409);
    }
    await this.audit(actor, input.id ? 'tag.update' : 'tag.create', 'tag', id, { category: input.category });
    return { id };
  }

  async listAudit() {
    const result = await this.database.execute({
      sql: 'SELECT id, actor, action, entity_type AS entityType, entity_id AS entityId, details, created_at AS createdAt FROM admin_audit_log ORDER BY created_at DESC, id DESC LIMIT 200',
    });
    return result.rows;
  }

  private async audit(actor: string, action: string, type: string, id: string, details: object) {
    await this.database.execute({
      sql: 'INSERT INTO admin_audit_log (id, actor, action, entity_type, entity_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      params: [crypto.randomUUID(), actor, action, type, id, JSON.stringify(details), this.now().toISOString()],
    });
  }
}
