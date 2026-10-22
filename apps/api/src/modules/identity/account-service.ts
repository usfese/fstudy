import { DomainError } from '../../core/errors.js';
import {
  createOpaqueToken,
  createPasswordCredential,
  hashLoginIdentifier,
  hashToken,
  verifyPassword,
} from '../../core/security.js';
import type { RuntimeDependencies } from '../../core/types.js';
import { InviteService } from '../invites/invite-service.js';

type LoginRow = {
  user_id: string;
  password_hash: string;
  password_salt: string;
  password_iterations: number;
  status: string;
};

export type PublicUser = {
  id: string;
  username: string | null;
  displayName: string;
  departmentId: string | null;
  bio: string;
  discoverable: boolean;
  scheduleVisibility: 'private' | 'busy_only' | 'course_name' | 'full';
  verifiedAt: string;
};

type UserRow = {
  id: string;
  username: string | null;
  display_name: string;
  department_id: string | null;
  bio: string;
  discoverable: number;
  schedule_visibility: PublicUser['scheduleVisibility'];
  verified_at: string;
};

const SESSION_DAYS = 30;
const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;
const AUTH_WINDOW_MS = 15 * 60 * 1000;
const AUTH_MAX_FAILURES = 5;
const DUMMY_PASSWORD_CREDENTIAL = {
  hash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  iterations: 100_000,
};

function normalizeUsername(value: string): string {
  return value.trim().toLowerCase();
}

function futureIso(now: Date, days: number): string {
  return new Date(now.getTime() + days * 86_400_000).toISOString();
}

function mapUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    departmentId: row.department_id,
    bio: row.bio,
    discoverable: row.discoverable === 1,
    scheduleVisibility: row.schedule_visibility,
    verifiedAt: row.verified_at,
  };
}

export class AccountService {
  private readonly invites: InviteService;

  constructor(private readonly dependencies: RuntimeDependencies) {
    this.invites = new InviteService(dependencies.database, dependencies.clock);
  }

  async completeVerifiedIdentityHash(input: {
    studentIdHash: string;
    displayName?: string;
    appPassword?: string;
    departmentId: string | null;
    allowExistingSession?: boolean;
  }): Promise<{ accessToken: string; expiresAt: string; user: PublicUser }> {
    // Legacy CAS login is kept only for accounts that predate username-only
    // registration. It can never create or upgrade an account (ADR-023).
    const identityHash = input.studentIdHash;
    const existing = await this.dependencies.database.execute<{ user_id: string }>({
      sql: 'SELECT user_id FROM student_identities WHERE student_id_hash = ?',
      params: [identityHash],
    });
    if (existing.rows.length === 0) {
      throw new DomainError('invite_registration_required', '新账户必须使用邀请码注册', 403);
    }
    if (!input.allowExistingSession) {
      throw new DomainError('student_already_registered', '该学生身份已经注册', 409);
    }
    return this.createSessionForVerifiedIdentityHash(identityHash);
  }

  private now(): Date {
    return (this.dependencies.clock ?? (() => new Date()))();
  }

  async createSessionForVerifiedIdentityHash(studentIdHash: string) {
    const result = await this.dependencies.database.execute<{ user_id: string; status: string }>({
      sql: `SELECT i.user_id, u.status FROM student_identities i
            JOIN users u ON u.id = i.user_id WHERE i.student_id_hash = ?`,
      params: [studentIdHash],
    });
    const row = result.rows[0];
    if (!row || row.status !== 'active') {
      throw new DomainError('student_not_registered', '该身份尚未创建 FStudy 账户', 404);
    }
    const now = this.now();
    const token = createOpaqueToken();
    const expiresAt = futureIso(now, SESSION_DAYS);
    await this.dependencies.database.execute({
      sql: `INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?)`,
      params: [crypto.randomUUID(), row.user_id, await hashToken(token), expiresAt, now.toISOString()],
    });
    return { accessToken: token, expiresAt, user: await this.getUser(row.user_id) };
  }

  private async assertAuthAllowed(throttleKey: string): Promise<void> {
    const result = await this.dependencies.database.execute<{
      blocked_until: string | null;
    }>({
      sql: 'SELECT blocked_until FROM auth_throttles WHERE throttle_key = ?',
      params: [throttleKey],
    });
    const blockedUntil = result.rows[0]?.blocked_until;
    const now = (this.dependencies.clock ?? (() => new Date()))();
    if (blockedUntil && new Date(blockedUntil) > now) {
      throw new DomainError(
        'authentication_rate_limited',
        '登录尝试过多，请稍后再试',
        429,
      );
    }
  }

  private async recordAuthFailure(throttleKey: string): Promise<void> {
    const now = (this.dependencies.clock ?? (() => new Date()))();
    const existing = await this.dependencies.database.execute<{
      failure_count: number;
      window_started_at: string;
    }>({
      sql: 'SELECT failure_count, window_started_at FROM auth_throttles WHERE throttle_key = ?',
      params: [throttleKey],
    });
    const row = existing.rows[0];
    const inWindow = row && now.getTime() - new Date(row.window_started_at).getTime() < AUTH_WINDOW_MS;
    const failures = inWindow ? row.failure_count + 1 : 1;
    const windowStartedAt = inWindow ? row.window_started_at : now.toISOString();
    const blockedUntil = failures >= AUTH_MAX_FAILURES
      ? new Date(now.getTime() + AUTH_WINDOW_MS).toISOString()
      : null;
    await this.dependencies.database.batch([
      {
        sql: 'DELETE FROM auth_throttles WHERE updated_at < ?',
        params: [new Date(now.getTime() - 86_400_000).toISOString()],
      },
      {
        sql: `INSERT INTO auth_throttles
              (throttle_key, failure_count, window_started_at, blocked_until, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(throttle_key) DO UPDATE SET
              failure_count = excluded.failure_count,
              window_started_at = excluded.window_started_at,
              blocked_until = excluded.blocked_until,
              updated_at = excluded.updated_at`,
        params: [throttleKey, failures, windowStartedAt, blockedUntil, now.toISOString()],
      },
    ]);
  }

  private async clearAuthFailures(throttleKey: string): Promise<void> {
    await this.dependencies.database.execute({
      sql: 'DELETE FROM auth_throttles WHERE throttle_key = ?',
      params: [throttleKey],
    });
  }

  async register(input: {
    username: string;
    email: string;
    appPassword: string;
    displayName?: string | undefined;
    departmentId: string | null;
    inviteCode: string;
  }): Promise<{ accessToken: string; expiresAt: string; user: PublicUser }> {
    const username = normalizeUsername(input.username);
    if (!USERNAME_PATTERN.test(username)) {
      throw new DomainError('invalid_username', '用户名需为 3–20 位字母、数字或下划线', 400);
    }
    const displayName = input.displayName?.trim() || input.username.trim();
    const email = input.email.trim().toLowerCase();
    const takenUsername = await this.dependencies.database.execute({
      sql: 'SELECT 1 FROM users WHERE username = ?',
      params: [username],
    });
    if (takenUsername.rows.length > 0) {
      throw new DomainError('username_already_registered', '该用户名已经被使用', 409);
    }
    const takenEmail = await this.dependencies.database.execute({
      sql: 'SELECT 1 FROM user_emails WHERE email = ?',
      params: [email],
    });
    if (takenEmail.rows.length > 0) {
      throw new DomainError('email_already_registered', '该邮箱已经注册', 409);
    }

    const now = this.now();
    const userId = crypto.randomUUID();
    const token = createOpaqueToken();
    const credential = await createPasswordCredential(input.appPassword);
    const createdAt = now.toISOString();
    const sessionExpiresAt = futureIso(now, SESSION_DAYS);
    const claim = await this.invites.claim(input.inviteCode, userId);
    try {
      await this.dependencies.database.batch([
        {
          sql: `INSERT INTO users
                (id, username, display_name, department_id, bio, discoverable, schedule_visibility, status, created_at)
                VALUES (?, ?, ?, ?, '', 0, 'busy_only', 'active', ?)`,
          params: [userId, username, displayName, input.departmentId, createdAt],
        },
        {
          sql: 'INSERT INTO credentials (user_id, password_hash, password_salt, password_iterations) VALUES (?, ?, ?, ?)',
          params: [userId, credential.hash, credential.salt, credential.iterations],
        },
        {
          sql: 'INSERT INTO user_emails (user_id, email, created_at) VALUES (?, ?, ?)',
          params: [userId, email, createdAt],
        },
        {
          sql: 'INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)',
          params: [crypto.randomUUID(), userId, await hashToken(token), sessionExpiresAt, createdAt],
        },
      ]);
    } catch (error) {
      await this.invites.release(claim);
      if (String(error).toLowerCase().includes('unique')) {
        throw new DomainError('registration_conflict', '该用户名或邮箱已经注册', 409);
      }
      throw error;
    }
    return {
      accessToken: token,
      expiresAt: sessionExpiresAt,
      user: {
        id: userId,
        username,
        displayName,
        departmentId: input.departmentId,
        bio: '',
        discoverable: false,
        scheduleVisibility: 'busy_only',
        verifiedAt: createdAt,
      },
    };
  }

  async login(input: { username: string; appPassword: string }) {
    const username = normalizeUsername(input.username);
    const throttleKey = `login:${await hashLoginIdentifier(username)}`;
    await this.assertAuthAllowed(throttleKey);
    const result = await this.dependencies.database.execute<LoginRow>({
      sql: `SELECT c.user_id, c.password_hash, c.password_salt, c.password_iterations, u.status
            FROM users u
            JOIN credentials c ON c.user_id = u.id
            WHERE u.username = ?`,
      params: [username],
    });
    const row = result.rows[0];
    const passwordMatches = await verifyPassword(
      input.appPassword,
      row
        ? {
            hash: row.password_hash,
            salt: row.password_salt,
            iterations: row.password_iterations,
          }
        : DUMMY_PASSWORD_CREDENTIAL,
    );
    if (
      !row ||
      row.status !== 'active' ||
      !passwordMatches
    ) {
      await this.recordAuthFailure(throttleKey);
      throw new DomainError('invalid_credentials', '用户名或本系统密码错误', 401);
    }
    await this.clearAuthFailures(throttleKey);

    const token = createOpaqueToken();
    const now = this.now();
    const expiresAt = futureIso(now, SESSION_DAYS);
    await this.dependencies.database.execute({
      sql: `INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?)`,
      params: [crypto.randomUUID(), row.user_id, await hashToken(token), expiresAt, now.toISOString()],
    });
    return { accessToken: token, expiresAt, user: await this.getUser(row.user_id) };
  }

  async authenticate(token: string | null): Promise<string> {
    if (!token) throw new DomainError('authentication_required', '需要登录', 401);
    const now = this.now().toISOString();
    const result = await this.dependencies.database.execute<{ user_id: string }>({
      sql: `SELECT s.user_id FROM sessions s
            JOIN users u ON u.id = s.user_id
            WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ?
              AND u.status = 'active'`,
      params: [await hashToken(token), now],
    });
    const row = result.rows[0];
    if (!row) throw new DomainError('invalid_session', '登录已失效', 401);
    return row.user_id;
  }

  async revokeSession(token: string): Promise<void> {
    await this.dependencies.database.execute({
      sql: 'UPDATE sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL',
      params: [
        (this.dependencies.clock ?? (() => new Date()))().toISOString(),
        await hashToken(token),
      ],
    });
  }

  async getEmail(userId: string): Promise<string | null> {
    const result = await this.dependencies.database.execute<{ email: string }>({
      sql: 'SELECT email FROM user_emails WHERE user_id = ?',
      params: [userId],
    });
    return result.rows[0]?.email ?? null;
  }

  async getUser(userId: string): Promise<PublicUser> {
    const result = await this.dependencies.database.execute<UserRow>({
      sql: `SELECT u.id, u.username, u.display_name, u.department_id, u.bio, u.discoverable,
                   u.schedule_visibility, COALESCE(i.verified_at, u.created_at) AS verified_at
            FROM users u LEFT JOIN student_identities i ON i.user_id = u.id WHERE u.id = ?`,
      params: [userId],
    });
    const row = result.rows[0];
    if (!row) throw new DomainError('user_not_found', '用户不存在', 404);
    return mapUser(row);
  }

  async updateUser(
    userId: string,
    input: {
      displayName: string;
      bio: string;
      departmentId: string | null;
      discoverable: boolean;
      scheduleVisibility: PublicUser['scheduleVisibility'];
    },
  ): Promise<PublicUser> {
    await this.dependencies.database.execute({
      sql: `UPDATE users SET display_name = ?, bio = ?, department_id = ?, discoverable = ?,
                   schedule_visibility = ? WHERE id = ?`,
      params: [
        input.displayName,
        input.bio,
        input.departmentId,
        input.discoverable ? 1 : 0,
        input.scheduleVisibility,
        userId,
      ],
    });
    return this.getUser(userId);
  }
}
