import { DomainError } from '../../core/errors.js';
import { hashToken } from '../../core/security.js';
import type { SqlDatabase } from '../../core/types.js';

export const INVITES_PER_MONTH = 5;

// Crockford base32: no I, L, O, U, so codes read unambiguously.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const CODE_LENGTH = 12;

/** Normalizes user input: case-insensitive, ignores separators, maps look-alike characters. */
export function normalizeInviteCode(input: string): string {
  return input.toUpperCase().replace(/[\s-]/g, '')
    .replace(/[IL]/g, '1').replace(/O/g, '0');
}

export function hashInviteCode(input: string): Promise<string> {
  return hashToken(normalizeInviteCode(input));
}

function generateCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  const raw = Array.from(bytes, (byte) => ALPHABET[byte % ALPHABET.length]).join('');
  return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8)}`;
}

/** Calendar month in Asia/Shanghai (UTC+8, no DST), used for the monthly quota. */
export function quotaMonth(now: Date): string {
  return new Date(now.getTime() + 8 * 3_600_000).toISOString().slice(0, 7);
}

export class InviteService {
  constructor(
    private readonly database: SqlDatabase,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  /** Issues one code for a user, if the user is still within this month's quota. */
  async issueForUser(userId: string): Promise<{ code: string; remainingThisMonth: number; month: string }> {
    const now = this.clock();
    const month = quotaMonth(now);
    const code = generateCode();
    const inserted = await this.database.execute({
      sql: `INSERT INTO invite_codes (id, code_hash, source, issued_by, issued_month, created_at)
            SELECT ?, ?, 'user', ?, ?, ?
            WHERE (SELECT COUNT(*) FROM invite_codes WHERE issued_by = ? AND issued_month = ?) < ?`,
      params: [
        crypto.randomUUID(), await hashInviteCode(code), userId, month, now.toISOString(),
        userId, month, INVITES_PER_MONTH,
      ],
    });
    if (inserted.changes !== 1) {
      throw new DomainError('invite_quota_exceeded', `本月邀请名额已用完（每人每月 ${INVITES_PER_MONTH} 个）`, 429);
    }
    return { code, remainingThisMonth: await this.remaining(userId), month };
  }

  /** Issues an operator code. These are not counted against any user's quota. */
  async issueByAdmin(): Promise<{ id: string; code: string }> {
    const now = this.clock();
    const code = generateCode();
    const id = crypto.randomUUID();
    await this.database.execute({
      sql: `INSERT INTO invite_codes (id, code_hash, source, issued_by, issued_month, created_at)
            VALUES (?, ?, 'admin', NULL, ?, ?)`,
      params: [id, await hashInviteCode(code), quotaMonth(now), now.toISOString()],
    });
    return { id, code };
  }

  async listForUser(userId: string) {
    const month = quotaMonth(this.clock());
    const rows = await this.database.execute<{ id: string; created_at: string; used_at: string | null }>({
      sql: `SELECT id, created_at, used_at FROM invite_codes
            WHERE issued_by = ? ORDER BY created_at DESC`,
      params: [userId],
    });
    return {
      month,
      quota: INVITES_PER_MONTH,
      remainingThisMonth: await this.remaining(userId),
      invites: rows.rows.map((row) => ({
        id: row.id,
        createdAt: row.created_at,
        status: row.used_at ? 'used' : 'unused',
        usedAt: row.used_at,
      })),
    };
  }

  /** Atomically claims an unused code for a new user. Call `release` if registration fails afterwards. */
  async claim(code: string, userId: string): Promise<{ codeHash: string; claimedAt: string }> {
    const codeHash = await hashInviteCode(code);
    const claimedAt = this.clock().toISOString();
    const result = await this.database.execute({
      sql: 'UPDATE invite_codes SET used_by = ?, used_at = ? WHERE code_hash = ? AND used_at IS NULL',
      params: [userId, claimedAt, codeHash],
    });
    if (result.changes !== 1) {
      throw new DomainError('invalid_invite_code', '邀请码无效或已被使用', 403);
    }
    return { codeHash, claimedAt };
  }

  async release(claim: { codeHash: string; claimedAt: string }): Promise<void> {
    await this.database.execute({
      sql: 'UPDATE invite_codes SET used_by = NULL, used_at = NULL WHERE code_hash = ? AND used_at = ?',
      params: [claim.codeHash, claim.claimedAt],
    });
  }

  private async remaining(userId: string): Promise<number> {
    const result = await this.database.execute<{ count: number }>({
      sql: 'SELECT COUNT(*) AS count FROM invite_codes WHERE issued_by = ? AND issued_month = ?',
      params: [userId, quotaMonth(this.clock())],
    });
    return Math.max(0, INVITES_PER_MONTH - (result.rows[0]?.count ?? 0));
  }
}
