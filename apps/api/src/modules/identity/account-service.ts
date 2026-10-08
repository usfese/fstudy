import { DomainError } from '../../core/errors.js';
import {
  createOpaqueToken,
  createPasswordCredential,
  hashStudentId,
  hashToken,
  verifyPassword,
} from '../../core/security.js';
import type { RuntimeDependencies } from '../../core/types.js';

type LoginRow = {
  user_id: string;
  password_hash: string;
  password_salt: string;
  password_iterations: number;
  status: string;
};

export type PublicUser = {
  id: string;
  displayName: string;
  departmentId: string | null;
  bio: string;
  discoverable: boolean;
  scheduleVisibility: 'private' | 'busy_only' | 'course_name' | 'full';
  verifiedAt: string;
};

type UserRow = {
  id: string;
  display_name: string;
  department_id: string | null;
  bio: string;
  discoverable: number;
  schedule_visibility: PublicUser['scheduleVisibility'];
  verified_at: string;
};

const SESSION_DAYS = 30;
const VERIFICATION_DAYS = 365;
const AUTH_WINDOW_MS = 15 * 60 * 1000;
const AUTH_MAX_FAILURES = 5;
const DUMMY_PASSWORD_CREDENTIAL = {
  hash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  iterations: 210_000,
};

function futureIso(now: Date, days: number): string {
  return new Date(now.getTime() + days * 86_400_000).toISOString();
}

function mapUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    displayName: row.display_name,
    departmentId: row.department_id,
    bio: row.bio,
    discoverable: row.discoverable === 1,
    scheduleVisibility: row.schedule_visibility,
    verifiedAt: row.verified_at,
  };
}

export class AccountService {
  constructor(private readonly dependencies: RuntimeDependencies) {}

  private async assertAuthAllowed(identityHash: string): Promise<void> {
    const result = await this.dependencies.database.execute<{
      blocked_until: string | null;
    }>({
      sql: 'SELECT blocked_until FROM auth_throttles WHERE throttle_key = ?',
      params: [identityHash],
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

  private async recordAuthFailure(identityHash: string): Promise<void> {
    const now = (this.dependencies.clock ?? (() => new Date()))();
    const existing = await this.dependencies.database.execute<{
      failure_count: number;
      window_started_at: string;
    }>({
      sql: 'SELECT failure_count, window_started_at FROM auth_throttles WHERE throttle_key = ?',
      params: [identityHash],
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
        params: [identityHash, failures, windowStartedAt, blockedUntil, now.toISOString()],
      },
    ]);
  }

  private async clearAuthFailures(identityHash: string): Promise<void> {
    await this.dependencies.database.execute({
      sql: 'DELETE FROM auth_throttles WHERE throttle_key = ?',
      params: [identityHash],
    });
  }

  async register(input: {
    studentId: string;
    schoolPassword: string;
    appPassword: string;
    displayName: string;
    departmentId: string | null;
  }): Promise<{ accessToken: string; expiresAt: string; user: PublicUser }> {
    const inputIdentityHash = await hashStudentId(input.studentId, this.dependencies.studentIdPepper);
    await this.assertAuthAllowed(inputIdentityHash);
    let verified;
    try {
      verified = await this.dependencies.studentVerifier.verify({
        studentId: input.studentId,
        password: input.schoolPassword,
        claimedDepartmentId: input.departmentId,
      });
    } catch (error) {
      await this.recordAuthFailure(inputIdentityHash);
      throw error;
    }
    await this.clearAuthFailures(inputIdentityHash);
    const identityHash = await hashStudentId(verified.studentId, this.dependencies.studentIdPepper);
    const existing = await this.dependencies.database.execute<{ user_id: string }>({
      sql: 'SELECT user_id FROM student_identities WHERE student_id_hash = ?',
      params: [identityHash],
    });
    if (existing.rows.length > 0) {
      throw new DomainError('student_already_registered', '该学生身份已经注册', 409);
    }

    const now = (this.dependencies.clock ?? (() => new Date()))();
    const userId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();
    const token = createOpaqueToken();
    const tokenHash = await hashToken(token);
    const credential = await createPasswordCredential(input.appPassword);
    const createdAt = now.toISOString();
    const sessionExpiresAt = futureIso(now, SESSION_DAYS);
    const verificationExpiresAt = futureIso(now, VERIFICATION_DAYS);
    const departmentId = verified.departmentId ?? input.departmentId;

    try {
      await this.dependencies.database.batch([
        {
          sql: `INSERT INTO users
            (id, display_name, department_id, bio, discoverable, schedule_visibility, status, created_at)
            VALUES (?, ?, ?, '', 0, 'busy_only', 'active', ?)`,
          params: [userId, input.displayName, departmentId, createdAt],
        },
        {
          sql: `INSERT INTO student_identities
            (user_id, student_id_hash, verified_department_id, verified_at, expires_at)
            VALUES (?, ?, ?, ?, ?)`,
          params: [
            userId,
            identityHash,
            verified.departmentId,
            createdAt,
            verificationExpiresAt,
          ],
        },
        {
          sql: `INSERT INTO credentials
            (user_id, password_hash, password_salt, password_iterations) VALUES (?, ?, ?, ?)`,
          params: [userId, credential.hash, credential.salt, credential.iterations],
        },
        {
          sql: `INSERT INTO sessions
            (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)`,
          params: [sessionId, userId, tokenHash, sessionExpiresAt, createdAt],
        },
      ]);
    } catch (error) {
      if (String(error).toLowerCase().includes('unique')) {
        throw new DomainError('student_already_registered', '该学生身份已经注册', 409);
      }
      throw error;
    }

    return {
      accessToken: token,
      expiresAt: sessionExpiresAt,
      user: {
        id: userId,
        displayName: input.displayName,
        departmentId,
        bio: '',
        discoverable: false,
        scheduleVisibility: 'busy_only',
        verifiedAt: createdAt,
      },
    };
  }

  async login(input: { studentId: string; appPassword: string }) {
    const identityHash = await hashStudentId(input.studentId, this.dependencies.studentIdPepper);
    await this.assertAuthAllowed(identityHash);
    const result = await this.dependencies.database.execute<LoginRow>({
      sql: `SELECT c.user_id, c.password_hash, c.password_salt, c.password_iterations, u.status
            FROM student_identities i
            JOIN credentials c ON c.user_id = i.user_id
            JOIN users u ON u.id = i.user_id
            WHERE i.student_id_hash = ?`,
      params: [identityHash],
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
      await this.recordAuthFailure(identityHash);
      throw new DomainError('invalid_credentials', '学号或本系统密码错误', 401);
    }
    await this.clearAuthFailures(identityHash);

    const token = createOpaqueToken();
    const now = (this.dependencies.clock ?? (() => new Date()))();
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
    const result = await this.dependencies.database.execute<{ user_id: string }>({
      sql: `SELECT s.user_id FROM sessions s
            JOIN users u ON u.id = s.user_id
            WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active'`,
      params: [await hashToken(token), (this.dependencies.clock ?? (() => new Date()))().toISOString()],
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

  async getUser(userId: string): Promise<PublicUser> {
    const result = await this.dependencies.database.execute<UserRow>({
      sql: `SELECT u.id, u.display_name, u.department_id, u.bio, u.discoverable,
                   u.schedule_visibility, i.verified_at
            FROM users u JOIN student_identities i ON i.user_id = u.id WHERE u.id = ?`,
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
