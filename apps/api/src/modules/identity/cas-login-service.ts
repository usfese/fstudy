import { DomainError } from '../../core/errors.js';
import {
  createOpaqueToken,
  hashStudentId,
  hashToken,
} from '../../core/security.js';
import type { RuntimeDependencies } from '../../core/types.js';
import { BuptCasStudentVerifier } from '../../adapters/student-verifier.js';
import type { AccountService } from './account-service.js';

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
// const CHALLENGE_TTL_MS = 5 * 60_000;
// const CHALLENGE_RATE_WINDOW_MS = 15 * 60_000;
// const CHALLENGE_RATE_LIMIT = 5;
// const CHALLENGE_MAX_ATTEMPTS = 3;

export type CasSession = Awaited<ReturnType<AccountService['completeVerifiedIdentityHash']>>;

// export type PasswordChallengeIssued = {
  // challengeId: string;
  // captchaImage: string | null;
  // expiresInSeconds: number;
// };

// export type PasswordVerifyOutcome =
  // | { kind: 'retry'; code: string; message: string }
  // | { kind: 'session'; session: CasSession };

// /** Browser-redirect CAS login. The password + captcha challenge flow is disabled (see comments). */
export class CasLoginService {
  private readonly browserVerifier = new BuptCasStudentVerifier();

  constructor(
    private readonly dependencies: RuntimeDependencies,
    private readonly accounts: AccountService,
    private readonly allowedOrigins: Set<string>,
  ) {}

  private get database() {
    return this.dependencies.database;
  }

  private now(): Date {
    return (this.dependencies.clock ?? (() => new Date()))();
  }

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // private get passwordVerifier(): BuptCasStudentVerifier {
    // return this.dependencies.studentVerifier as BuptCasStudentVerifier;
  // }

  private assertBrowserLoginEnabled(): void {
    if (!this.dependencies.casLoginEnabled) {
      throw new DomainError('cas_login_disabled', '北邮跳转认证尚未启用', 503);
    }
  }

  // private assertPasswordFlowEnabled(): void {
    // if (!this.dependencies.schoolPasswordRegistrationEnabled || !(this.dependencies.studentVerifier instanceof BuptCasStudentVerifier)) {
      // throw new DomainError('school_password_registration_disabled', '学校密码认证未启用', 503);
    // }
    // if (!this.dependencies.casStateEncryptionKey || this.dependencies.casStateEncryptionKey.length < 32) {
      // throw new DomainError('cas_challenge_unavailable', '验证码服务未完成安全配置', 503);
    // }
  // }

  // private assertOriginAllowed(origin: string | undefined): void {
    // if (!origin || !this.allowedOrigins.has(origin)) {
      // throw new DomainError('cas_origin_not_allowed', '认证来源不受支持', 403);
    // }
  // }

  async startBrowserLogin(origin: string | undefined): Promise<{ authorizationUrl: string }> {
    this.assertBrowserLoginEnabled();
    const callbackBaseUrl = this.dependencies.casCallbackUrl;
    if (!callbackBaseUrl) {
      throw new DomainError('cas_not_configured', '北邮浏览器认证回调地址尚未配置', 503);
    }
    const parsed = new URL(callbackBaseUrl);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.search || parsed.hash) {
      throw new DomainError('cas_not_configured', '北邮认证回调地址配置不受支持', 503);
    }
    if (!origin || !this.allowedOrigins.has(origin)) {
      throw new DomainError('cas_origin_not_allowed', '认证发起来源不受支持', 403);
    }
    const state = createOpaqueToken();
    const now = this.now();
    await this.database.execute({
      sql: 'INSERT INTO cas_login_states (state_hash, return_origin, expires_at, created_at) VALUES (?, ?, ?, ?)',
      params: [await hashToken(state), origin, new Date(now.getTime() + 5 * 60_000).toISOString(), now.toISOString()],
    });
    const callbackUrl = new URL(callbackBaseUrl);
    callbackUrl.searchParams.set('state', state);
    return { authorizationUrl: await this.browserVerifier.authorizationUrl(callbackUrl.toString()) };
  }

  /** Validates the CAS ticket and returns the FStudy page URL the browser should be redirected to. */
  async handleBrowserCallback(ticket: string | undefined, state: string | undefined): Promise<string> {
    this.assertBrowserLoginEnabled();
    const callbackBaseUrl = this.dependencies.casCallbackUrl;
    if (!callbackBaseUrl || !ticket || !state || ticket.length > 4096 || state.length > 128) {
      throw new DomainError('invalid_cas_callback', '北邮认证回调参数无效', 400);
    }
    const stateHash = await hashToken(state);
    const stateResult = await this.database.execute<{ return_origin: string; expires_at: string; used_at: string | null }>({
      sql: 'SELECT return_origin, expires_at, used_at FROM cas_login_states WHERE state_hash = ?',
      params: [stateHash],
    });
    const loginState = stateResult.rows[0];
    if (!loginState || loginState.used_at || new Date(loginState.expires_at) <= this.now()) {
      throw new DomainError('invalid_cas_state', '登录状态已失效，请重新开始', 400);
    }
    const consumed = await this.database.execute({
      sql: 'UPDATE cas_login_states SET used_at = ? WHERE state_hash = ? AND used_at IS NULL',
      params: [this.now().toISOString(), stateHash],
    });
    if (consumed.changes !== 1) throw new DomainError('invalid_cas_state', '登录状态已失效，请重新开始', 400);
    const serviceUrl = new URL(callbackBaseUrl);
    serviceUrl.searchParams.set('state', state);
    const verified = await this.browserVerifier.verifyTicket(ticket, serviceUrl.toString());
    const code = createOpaqueToken();
    const now = this.now();
    await this.database.execute({
      sql: 'INSERT INTO cas_login_codes (code_hash, state_hash, student_id_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)',
      params: [
        await hashToken(code), stateHash,
        await hashStudentId(verified.studentId, this.dependencies.studentIdPepper),
        new Date(now.getTime() + 2 * 60_000).toISOString(), now.toISOString(),
      ],
    });
    const returnOrigin = loginState.return_origin;
    if (!returnOrigin || !this.allowedOrigins.has(returnOrigin)) {
      throw new DomainError('invalid_cas_return_origin', '返回地址无效', 400);
    }
    const returnUrl = new URL('/login', returnOrigin);
    returnUrl.hash = new URLSearchParams({ cas_code: code, cas_state: state }).toString();
    return returnUrl.toString();
  }

  async completeBrowserLogin(input: {
    code: string;
    state: string;
    origin: string | undefined;
    displayName?: string | undefined;
    appPassword?: string | undefined;
    departmentId: string | null;
  }): Promise<CasSession> {
    this.assertBrowserLoginEnabled();
    const codeHash = await hashToken(input.code);
    const stateHash = await hashToken(input.state);
    const result = await this.database.execute<{
      student_id_hash: string; expires_at: string; used_at: string | null; return_origin: string;
    }>({
      sql: `SELECT c.student_id_hash, c.expires_at, c.used_at, s.return_origin
            FROM cas_login_codes c JOIN cas_login_states s ON s.state_hash = c.state_hash
            WHERE c.code_hash = ? AND c.state_hash = ?`,
      params: [codeHash, stateHash],
    });
    const verified = result.rows[0];
    if (!verified || verified.used_at || new Date(verified.expires_at) <= this.now()) {
      throw new DomainError('invalid_cas_code', '认证结果已失效，请重新开始', 400);
    }
    if ((input.origin && input.origin !== verified.return_origin) || !this.allowedOrigins.has(verified.return_origin)) {
      throw new DomainError('invalid_cas_return_origin', '认证返回来源无效', 403);
    }
    const existingIdentity = await this.database.execute<{ user_id: string }>({
      sql: 'SELECT user_id FROM student_identities WHERE student_id_hash = ?',
      params: [verified.student_id_hash],
    });
    if (existingIdentity.rows.length === 0 && (!input.displayName || !input.appPassword)) {
      throw new DomainError('cas_registration_required', '认证成功。首次使用请补充 FStudy 显示名称和本系统密码。', 409);
    }
    const consumed = await this.database.execute({
      sql: 'UPDATE cas_login_codes SET used_at = ? WHERE code_hash = ? AND state_hash = ? AND used_at IS NULL AND expires_at > ?',
      params: [this.now().toISOString(), codeHash, stateHash, this.now().toISOString()],
    });
    if (consumed.changes !== 1) throw new DomainError('invalid_cas_code', '认证结果已失效，请重新开始', 400);
    return this.accounts.completeVerifiedIdentityHash({
      studentIdHash: verified.student_id_hash,
      ...(input.displayName === undefined ? {} : { displayName: input.displayName }),
      ...(input.appPassword === undefined ? {} : { appPassword: input.appPassword }),
      departmentId: input.departmentId,
      allowExistingSession: true,
    });
  }

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // async issuePasswordChallenge(origin: string | undefined, studentId: string): Promise<PasswordChallengeIssued> {
    // this.assertPasswordFlowEnabled();
    // this.assertOriginAllowed(origin);
    // const studentIdHash = await hashStudentId(studentId, this.dependencies.studentIdPepper);
    // const recent = await this.database.execute<{ count: number }>({
      // sql: 'SELECT COUNT(*) AS count FROM cas_password_challenges WHERE student_id_hash = ? AND created_at > ?',
      // params: [studentIdHash, new Date(Date.now() - CHALLENGE_RATE_WINDOW_MS).toISOString()],
    // });
    // if ((recent.rows[0]?.count ?? 0) >= CHALLENGE_RATE_LIMIT) {
      // throw new DomainError('cas_challenge_rate_limited', '验证码请求过于频繁，请 15 分钟后重试', 429);
    // }
    // await this.database.execute({
      // sql: 'DELETE FROM cas_password_challenges WHERE expires_at <= ? OR consumed_at IS NOT NULL',
      // params: [this.now().toISOString()],
    // });
    // return this.createChallenge(studentIdHash);
  // }

  // async refreshPasswordChallenge(challengeId: string, studentId: string): Promise<PasswordChallengeIssued> {
    // this.assertPasswordFlowEnabled();
    // const challengeHash = await hashToken(challengeId);
    // const challenge = await this.database.execute<{ student_id_hash: string; expires_at: string; consumed_at: string | null }>({
      // sql: 'SELECT student_id_hash, expires_at, consumed_at FROM cas_password_challenges WHERE challenge_hash = ?',
      // params: [challengeHash],
    // });
    // const prior = challenge.rows[0];
    // if (!prior || prior.consumed_at || new Date(prior.expires_at) <= this.now()) {
      // throw new DomainError('cas_challenge_expired', '验证码已过期，请重新获取', 400);
    // }
    // const studentIdHash = await hashStudentId(studentId, this.dependencies.studentIdPepper);
    // if (studentIdHash !== prior.student_id_hash) {
      // throw new DomainError('cas_challenge_identity_mismatch', '学号与验证码会话不一致', 400);
    // }
    // const recent = await this.database.execute<{ count: number }>({
      // sql: 'SELECT COUNT(*) AS count FROM cas_password_challenges WHERE student_id_hash = ? AND created_at > ?',
      // params: [studentIdHash, new Date(Date.now() - CHALLENGE_RATE_WINDOW_MS).toISOString()],
    // });
    // if ((recent.rows[0]?.count ?? 0) >= CHALLENGE_RATE_LIMIT) {
      // throw new DomainError('cas_challenge_rate_limited', '验证码请求过于频繁，请稍后再试', 429);
    // }
    // const consumed = await this.database.execute({
      // sql: 'UPDATE cas_password_challenges SET consumed_at = ? WHERE challenge_hash = ? AND consumed_at IS NULL AND expires_at > ?',
      // params: [this.now().toISOString(), challengeHash, this.now().toISOString()],
    // });
    // if (consumed.changes !== 1) throw new DomainError('cas_challenge_expired', '验证码已使用或过期', 400);
    // return this.createChallenge(studentIdHash);
  // }

  // async verifyPasswordChallenge(input: {
    // challengeId: string;
    // studentId: string;
    // schoolPassword: string;
    // captcha?: string | null | undefined;
    // displayName: string;
    // appPassword: string;
    // departmentId: string | null;
  // }): Promise<PasswordVerifyOutcome> {
    // this.assertPasswordFlowEnabled();
    // const challengeHash = await hashToken(input.challengeId);
    // const challenge = await this.database.execute<{ student_id_hash: string; encrypted_state: string; expires_at: string; consumed_at: string | null; attempt_count: number }>({
      // sql: 'SELECT student_id_hash, encrypted_state, expires_at, consumed_at, attempt_count FROM cas_password_challenges WHERE challenge_hash = ?',
      // params: [challengeHash],
    // });
    // const row = challenge.rows[0];
    // if (!row || row.consumed_at || new Date(row.expires_at) <= this.now()) {
      // throw new DomainError('cas_challenge_expired', '验证码已过期，请重新获取', 400);
    // }
    // const inputIdentityHash = await hashStudentId(input.studentId, this.dependencies.studentIdPepper);
    // if (inputIdentityHash !== row.student_id_hash) {
      // throw new DomainError('cas_challenge_identity_mismatch', '学号与验证码会话不一致，请重新获取', 400);
    // }
    // const attempt = await this.database.execute({
      // sql: 'UPDATE cas_password_challenges SET attempt_count = attempt_count + 1 WHERE challenge_hash = ? AND consumed_at IS NULL AND expires_at > ? AND attempt_count < ?',
      // params: [challengeHash, this.now().toISOString(), CHALLENGE_MAX_ATTEMPTS],
    // });
    // if (attempt.changes !== 1) throw new DomainError('cas_challenge_expired', '验证码已使用、过期或尝试次数已用完，请重新获取', 400);
    // const attemptCount = await this.database.execute<{ attempt_count: number }>({
      // sql: 'SELECT attempt_count FROM cas_password_challenges WHERE challenge_hash = ?',
      // params: [challengeHash],
    // });
    // let state: { cookie: string; execution: string; captchaId: string | null };
    // try {
      // state = JSON.parse(await decryptCasState(row.encrypted_state, this.dependencies.casStateEncryptionKey!));
    // } catch {
      // await this.clearChallenge(challengeHash);
      // throw new DomainError('cas_challenge_unavailable', '验证码会话无效，请重新获取', 400);
    // }
    // let verified: { studentId: string };
    // try {
      // verified = await this.passwordVerifier.verifyPasswordChallenge({
        // studentId: input.studentId,
        // password: input.schoolPassword,
        // captcha: input.captcha ?? null,
        // state,
      // });
    // } catch (error) {
      // if (error instanceof DomainError && error.code === 'school_auth_captcha_invalid'
        // && (attemptCount.rows[0]?.attempt_count ?? CHALLENGE_MAX_ATTEMPTS) < CHALLENGE_MAX_ATTEMPTS) {
        // return { kind: 'retry', code: error.code, message: error.message };
      // }
      // await this.clearChallenge(challengeHash);
      // throw error;
    // }
    // await this.clearChallenge(challengeHash);
    // await this.database.execute({
      // sql: 'DELETE FROM cas_password_challenges WHERE challenge_hash = ?',
      // params: [challengeHash],
    // });
    // const identityHash = await hashStudentId(verified.studentId, this.dependencies.studentIdPepper);
    // const renewed = await this.accounts.renewIdentityIfExpired(identityHash);
    // if (renewed) return { kind: 'session', session: renewed };
    // const session = await this.accounts.completeVerifiedIdentityHash({
      // studentIdHash: identityHash,
      // displayName: input.displayName,
      // appPassword: input.appPassword,
      // departmentId: input.departmentId,
    // });
    // return { kind: 'session', session };
  // }

  // private async createChallenge(studentIdHash: string): Promise<PasswordChallengeIssued> {
    // const challenge = await this.passwordVerifier.beginPasswordChallenge();
    // const challengeId = createOpaqueToken();
    // const now = this.now();
    // await this.database.execute({
      // sql: `INSERT INTO cas_password_challenges
        // (challenge_hash, student_id_hash, encrypted_state, expires_at, created_at)
        // VALUES (?, ?, ?, ?, ?)`,
      // params: [
        // await hashToken(challengeId),
        // studentIdHash,
        // await encryptCasState(JSON.stringify(challenge.state), this.dependencies.casStateEncryptionKey!),
        // new Date(now.getTime() + CHALLENGE_TTL_MS).toISOString(),
        // now.toISOString(),
      // ],
    // });
    // return { challengeId, captchaImage: challenge.captchaImage, expiresInSeconds: 300 };
  // }

  // private async clearChallenge(challengeHash: string): Promise<void> {
    // await this.database.execute({
      // sql: 'UPDATE cas_password_challenges SET consumed_at = ?, encrypted_state = ? WHERE challenge_hash = ?',
      // params: [this.now().toISOString(), '', challengeHash],
    // });
  // }
}
