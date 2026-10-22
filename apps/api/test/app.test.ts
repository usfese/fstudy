import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { NodeSqliteDatabase } from '../src/adapters/node-database.js';
import { BuptCasStudentVerifier } from '../src/adapters/student-verifier.js';
import { DomainError } from '../src/core/errors.js';
import { hashInviteCode } from '../src/modules/invites/invite-service.js';
import { createApp } from '../src/http/app.js';
import { AdminService } from '../src/modules/admin/admin-service.js';

async function testApp({ casLoginEnabled = true, inviteRegistrationEnabled = true, clock }: {
  casLoginEnabled?: boolean;
  inviteRegistrationEnabled?: boolean;
  clock?: () => Date;
} = {}) {
  const database = new NodeSqliteDatabase(':memory:');
  latestDatabase = database;
  for (const migration of [
    '0001_initial', '0002_plans', '0003_friends', '0004_availability', '0005_auth_throttles',
    '0006_projects', '0007_forum', '0008_admin', '0009_academic_settings', '0010_notifications',
    '0011_cas_browser_login', '0012_cas_password_challenges', '0013_cas_challenge_attempts',
    '0014_invites_and_email', '0015_usernames',
  ]) {
    database.applyMigration(readFileSync(new URL(`../migrations/${migration}.sql`, import.meta.url), 'utf8'));
  }
  invitePool = [];
  for (let index = 0; index < 60; index += 1) {
    const code = `TEST-INVITE-${String(index).padStart(3, '0')}`;
    invitePool.push(code);
    await database.execute({
      sql: `INSERT INTO invite_codes (id, code_hash, source, issued_by, issued_month, created_at)
            VALUES (?, ?, 'admin', NULL, '2026-10', '2026-10-01T00:00:00.000Z')`,
      params: [`seed-${index}`, await hashInviteCode(code)],
    });
  }
  const dependencies = {
    database,
    studentIdPepper: 'test-pepper',
    allowedOrigins: ['http://127.0.0.1:8080'],
    adminBootstrapUsername: 'operator',
    adminBootstrapPassword: 'a-very-long-test-admin-password',
    casCallbackUrl: 'https://api.example.test/v1/auth/cas/callback',
    casLoginEnabled,
    inviteRegistrationEnabled,
    ...(clock ? { clock } : {}),
  };
  await new AdminService(dependencies).bootstrap();
  return createApp(dependencies);
}

let invitePool: string[] = [];
let latestDatabase: NodeSqliteDatabase;

afterEach(() => vi.unstubAllGlobals());

async function register(
  app: ReturnType<typeof createApp>,
  input: { username?: string; displayName?: string; departmentId?: string; email?: string; inviteCode?: string } = {},
) {
  const username = input.username ?? '20260001';
  const response = await app.request('/v1/auth/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      username,
      email: input.email ?? `${username}@example.edu`,
      appPassword: 'correct-horse-battery',
      displayName: input.displayName ?? '测试同学',
      departmentId: input.departmentId ?? 'computer',
      inviteCode: input.inviteCode ?? invitePool.shift(),
    }),
  });
  expect(response.status).toBe(201);
  return (await response.json()) as { accessToken: string; user: { id: string } };
}

describe('FStudy API', () => {
  it('applies API security headers and restricts browser origins', async () => {
    const app = await testApp();
    const allowed = await app.request('/health', {
      headers: { origin: 'http://127.0.0.1:8080' },
    });
    expect(allowed.headers.get('access-control-allow-origin')).toBe('http://127.0.0.1:8080');
    expect(allowed.headers.get('cache-control')).toBe('no-store');
    expect(allowed.headers.get('x-content-type-options')).toBe('nosniff');
    expect(allowed.headers.get('x-request-id')).toMatch(/^[0-9a-f-]{36}$/);

    const denied = await app.request('/health', {
      headers: { origin: 'https://attacker.example' },
    });
    expect(denied.headers.get('access-control-allow-origin')).toBeNull();
  });

  it('rejects unsupported and oversized request bodies', async () => {
    const app = await testApp();
    const unsupported = await app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: '{}',
    });
    expect(unsupported.status).toBe(415);
    expect(await unsupported.json()).toEqual({
      error: { code: 'unsupported_media_type', message: '请求必须使用 application/json' },
    });

    const oversized = await app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: '20260001', appPassword: 'x'.repeat(70_000) }),
    });
    expect(oversized.status).toBe(413);
    expect(await oversized.json()).toEqual({
      error: { code: 'request_too_large', message: '请求体过大' },
    });
  });

  it('rejects malformed bearer tokens before session lookup', async () => {
    const app = await testApp();
    const response = await app.request('/v1/me', {
      headers: { authorization: `Bearer ${'x'.repeat(5000)}` },
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      error: { code: 'authentication_required', message: '需要登录' },
    });
  });

  it('registers with an invite code, records the email, and never accepts a school password', async () => {
    const app = await testApp();
    const registration = await register(app, { email: 'Student.One@Example.edu' });
    const profile = await app.request('/v1/me', {
      headers: { authorization: `Bearer ${registration.accessToken}` },
    });
    expect(profile.status).toBe(200);
    expect(await profile.json()).toMatchObject({
      user: { displayName: '测试同学', departmentId: 'computer', discoverable: false },
      email: 'student.one@example.edu',
    });
    const stored = await latestDatabase.execute<{ email: string }>({ sql: 'SELECT email FROM user_emails' });
    expect(stored.rows).toEqual([{ email: 'student.one@example.edu' }]);

    const duplicateStudent = await app.request('/v1/auth/register', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: '20260001', email: 'other@example.edu', appPassword: 'another-password',
        displayName: '另一个账户', departmentId: 'computer', inviteCode: invitePool.shift(),
      }),
    });
    expect(duplicateStudent.status).toBe(409);
    expect(await duplicateStudent.json()).toMatchObject({ error: { code: 'username_already_registered' } });
  });

  it('refuses CAS browser login when the feature flag is off', async () => {
    const app = await testApp({ casLoginEnabled: false });
    const response = await app.request('/v1/auth/cas/start', {
      method: 'POST',
      headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      body: '{}',
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({
      error: { code: 'cas_login_disabled' },
    });
  });

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // it('requires captcha rather than accepting an unchallenged CAS password submission', async () => {
    // const verifier = new BuptCasStudentVerifier();
    // vi.spyOn(verifier, 'verify').mockRejectedValue(
      // new DomainError('school_auth_captcha_required', '学校认证要求验证码', 503),
    // );
    // const app = await testApp({ studentVerifier: verifier, schoolPasswordRegistrationEnabled: true });
    // const response = await app.request('/v1/auth/register', {
      // method: 'POST',
      // headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      // body: JSON.stringify({
        // studentId: '20260055', schoolPassword: 'school-secret',
        // appPassword: 'correct-horse-battery', displayName: 'test', departmentId: null,
      // }),
    // });
    // expect(response.status).toBe(503);
    // expect(await response.json()).toMatchObject({
      // error: { code: 'school_auth_captcha_required' },
    // });
  // });

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // it('stores only encrypted CAS challenge state, rate-limits issuance, and consumes a challenge once', async () => {
    // const verifier = new BuptCasStudentVerifier();
    // vi.spyOn(verifier, 'beginPasswordChallenge').mockResolvedValue({
      // state: { cookie: 'secret-cookie', execution: 'exec-secret', captchaId: 'captcha-1' },
      // captchaImage: 'data:image/png;base64,AQID',
    // });
    // vi.spyOn(verifier, 'verifyPasswordChallenge').mockImplementation(async (input) => ({
      // studentId: input.studentId,
    // }));
    // const app = await testApp({ studentVerifier: verifier, schoolPasswordRegistrationEnabled: true });
    // const database = latestDatabase;
    // const originalFetch = globalThis.fetch;
    // vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      // if (String(input).includes('/authserver/captcha')) {
        // return new Response(new Uint8Array([1, 2, 3]), {
          // status: 200,
          // headers: { 'content-type': 'image/png' },
        // });
      // }
      // return new Response('<html><input name="execution" value="exec-1">config.captcha { id: \'cid-1\' }</html>', {
        // status: 200,
        // headers: { 'set-cookie': 'SESSION=secret-cookie; Path=/; Secure' },
      // });
    // }));
    // const headers = { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' };
    // const challenge = await app.request('/v1/auth/cas/password/challenge', {
      // method: 'POST', headers, body: JSON.stringify({ studentId: '20260077' }),
    // });
    // expect(challenge.status).toBe(200);
    // const body = await challenge.json() as { challengeId: string; captchaImage: string };
    // expect(body.captchaImage).toContain('data:image/png;base64,');
    // const stored = await latestDatabase.execute<{ encrypted_state: string }>({
      // sql: 'SELECT encrypted_state FROM cas_password_challenges',
    // });
    // expect(stored.rows[0]!.encrypted_state).not.toContain('secret-cookie');
    // expect(stored.rows[0]!.encrypted_state).not.toContain('exec-1');
    // for (let index = 0; index < 4; index += 1) {
      // const issued = await app.request('/v1/auth/cas/password/challenge', {
        // method: 'POST', headers, body: JSON.stringify({ studentId: '20260077' }),
      // });
      // expect(issued.status).toBe(200);
    // }
    // const rateLimited = await app.request('/v1/auth/cas/password/challenge', {
      // method: 'POST', headers, body: JSON.stringify({ studentId: '20260077' }),
    // });
    // expect(rateLimited.status).toBe(429);

    // vi.spyOn(verifier, 'verifyPasswordChallenge').mockImplementationOnce(async (input) => ({
      // studentId: input.studentId,
    // }));
    // const verified = await app.request('/v1/auth/cas/password/verify', {
      // method: 'POST', headers,
      // body: JSON.stringify({
        // challengeId: body.challengeId, studentId: '20260077', schoolPassword: 'one-time-secret',
        // captcha: '1234', displayName: '验证码测试', appPassword: 'correct-horse-battery',
      // }),
    // });
    // expect(verified.status).toBe(201);
    // const replay = await app.request('/v1/auth/cas/password/verify', {
      // method: 'POST', headers,
      // body: JSON.stringify({
        // challengeId: body.challengeId, studentId: '20260077', schoolPassword: 'one-time-secret',
        // captcha: '1234', displayName: '验证码测试', appPassword: 'correct-horse-battery',
      // }),
    // });
    // expect(replay.status).toBe(400);
    // vi.stubGlobal('fetch', originalFetch);
  // });

  it('binds browser CAS state to a one-time code and refuses to mint accounts', async () => {
    const app = await testApp();
    await register(app, { username: '20261234', displayName: '邀请码注册同学' });
    const calls: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      calls.push(url);
      expect(url).toMatch(/^https:\/\/auth\.bupt\.edu\.cn\/authserver\/serviceValidate/);
      const parsed = new URL(url);
      expect(parsed.searchParams.get('service')).toContain('state=');
      const studentId = parsed.searchParams.get('ticket') === 'ST-new-account'
        ? '20261235'
        : '20261234';
      return new Response(`<?xml version="1.0"?><cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas"><cas:authenticationSuccess><cas:user>${studentId}</cas:user><cas:attributes><cas:uid>${studentId}</cas:uid></cas:attributes></cas:authenticationSuccess></cas:serviceResponse>`, { status: 200 });
    }));

    const started = await app.request('/v1/auth/cas/start', {
      method: 'POST',
      headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      body: '{}',
    });
    expect(started.status).toBe(200);
    const authorizationUrl = new URL(((await started.json()) as { authorizationUrl: string }).authorizationUrl);
    const service = new URL(authorizationUrl.searchParams.get('service')!);
    const state = service.searchParams.get('state')!;

    const callback = await app.request(`/v1/auth/cas/callback?ticket=ST-mock-ticket&state=${encodeURIComponent(state)}`);
    expect(callback.status).toBe(303);
    const returned = new URL(callback.headers.get('location')!);
    const callbackFragment = new URLSearchParams(returned.hash.slice(1));
    const code = callbackFragment.get('cas_code')!;
    expect(callbackFragment.get('cas_state')).toBe(state);
    expect(calls).toHaveLength(1);

    const completed = await app.request('/v1/auth/cas/complete', {
      method: 'POST',
      headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      body: JSON.stringify({
        code,
        state,
        displayName: 'CAS 测试同学',
        appPassword: 'correct-horse-battery',
        departmentId: null,
      }),
    });
    expect(completed.status).toBe(403);
    expect(await completed.json()).toMatchObject({ error: { code: 'invite_registration_required' } });

    const replay = await app.request('/v1/auth/cas/complete', {
      method: 'POST',
      headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      body: JSON.stringify({ code, state, displayName: 'CAS 测试同学', appPassword: 'correct-horse-battery' }),
    });
    expect(replay.status).toBe(400);

    const secondStarted = await app.request('/v1/auth/cas/start', {
      method: 'POST', headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' }, body: '{}',
    });
    const secondAuthorizationUrl = new URL(((await secondStarted.json()) as { authorizationUrl: string }).authorizationUrl);
    const secondState = new URL(secondAuthorizationUrl.searchParams.get('service')!).searchParams.get('state')!;
    const secondCallback = await app.request(`/v1/auth/cas/callback?ticket=ST-new-account&state=${encodeURIComponent(secondState)}`);
    const secondCode = new URLSearchParams(new URL(secondCallback.headers.get('location')!).hash.slice(1)).get('cas_code')!;
    const bypass = await app.request('/v1/auth/cas/complete', {
      method: 'POST', headers: { origin: 'http://127.0.0.1:8080', 'content-type': 'application/json' },
      body: JSON.stringify({ code: secondCode, state: secondState, displayName: '绕过邀请', appPassword: 'correct-horse-battery' }),
    });
    expect(bypass.status).toBe(403);
    expect(await bypass.json()).toMatchObject({ error: { code: 'invite_registration_required' } });
  });

  it('rate limits repeated login failures and revokes logout sessions', async () => {
    const app = await testApp();
    const { accessToken } = await register(app);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const failed = await app.request('/v1/auth/login', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ username: '20260001', appPassword: 'wrong-password' }),
      });
      expect(failed.status).toBe(401);
    }
    const blocked = await app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: '20260001', appPassword: 'correct-horse-battery' }),
    });
    expect(blocked.status).toBe(429);
    expect(await blocked.json()).toEqual({
      error: { code: 'authentication_rate_limited', message: '登录尝试过多，请稍后再试' },
    });

    const logout = await app.request('/v1/auth/logout', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json',
      },
    });
    expect(logout.status).toBe(200);
    const revoked = await app.request('/v1/me', {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(revoked.status).toBe(401);
  });

  it('returns the same login error for unknown accounts and wrong passwords', async () => {
    const app = await testApp();
    await register(app);
    const attempt = (username: string) => app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username, appPassword: 'wrong-password' }),
    });
    const unknown = await attempt('20269999');
    const existing = await attempt('20260001');
    expect(unknown.status).toBe(401);
    expect(existing.status).toBe(401);
    expect(await unknown.json()).toEqual(await existing.json());
  });

  it('creates and lists a manually entered course', async () => {
    const app = await testApp();
    const { accessToken } = await register(app);
    const headers = { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' };
    const created = await app.request('/v1/courses', {
      method: 'POST', headers,
      body: JSON.stringify({
        name: '计算机网络', teacher: '张老师', color: '#3366FF',
        meetings: [{
          weekday: 1, startMinute: 480, endMinute: 570, startWeek: 1, endWeek: 16,
          weekParity: 'all', campus: '沙河', building: '教学实验综合楼', room: 'S2-101',
        }],
      }),
    });
    expect(created.status).toBe(201);

    const listed = await app.request('/v1/courses', { headers });
    expect(listed.status).toBe(200);
    expect(await listed.json()).toMatchObject({
      courses: [{ name: '计算机网络', meetings: [{ weekday: 1, room: 'S2-101' }] }],
    });
  });

  it('edits, deletes and clears courses with ownership checks', async () => {
    const app = await testApp();
    const owner = await register(app, { username: '20260401' });
    const other = await register(app, { username: '20260402' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    const courseInput = {
      name: '计算机网络',
      teacher: '张老师',
      color: '#3366FF',
      meetings: [{
        weekday: 1, startMinute: 480, endMinute: 570, startWeek: 1, endWeek: 16,
        weekParity: 'all', campus: null, building: null, room: 'S2-101',
      }],
    };
    const created = await app.request('/v1/courses', {
      method: 'POST', headers: headers(owner.accessToken), body: JSON.stringify(courseInput),
    });
    const { course } = await created.json() as { course: { id: string } };

    const updated = await app.request(`/v1/courses/${course.id}`, {
      method: 'PUT', headers: headers(owner.accessToken),
      body: JSON.stringify({
        ...courseInput,
        name: '计算机网络（实验）',
        meetings: [{
          weekday: 2, startMinute: 600, endMinute: 635, startWeek: 3, endWeek: 12,
          weekParity: 'odd', campus: null, building: null, room: 'S3-202',
        }],
      }),
    });
    expect(updated.status).toBe(200);
    expect(await (await app.request('/v1/courses', { headers: headers(owner.accessToken) })).json())
      .toMatchObject({
        courses: [{
          name: '计算机网络（实验）',
          meetings: [{ weekday: 2, startMinute: 600, room: 'S3-202' }],
        }],
      });

    const foreignDelete = await app.request(`/v1/courses/${course.id}`, {
      method: 'DELETE', headers: headers(other.accessToken),
    });
    expect(foreignDelete.status).toBe(404);

    const deleted = await app.request(`/v1/courses/${course.id}`, {
      method: 'DELETE', headers: headers(owner.accessToken),
    });
    expect(deleted.status).toBe(200);

    const recreated = await app.request('/v1/courses', {
      method: 'POST', headers: headers(owner.accessToken), body: JSON.stringify(courseInput),
    });
    const recreatedCourse = ((await recreated.json()) as { course: { id: string } }).course;
    await app.request('/v1/assignments', {
      method: 'POST', headers: headers(owner.accessToken),
      body: JSON.stringify({
        title: '课程作业', notes: '', courseId: recreatedCourse.id, dueAt: null,
      }),
    });
    const cleared = await app.request('/v1/courses', {
      method: 'DELETE', headers: headers(owner.accessToken),
    });
    expect(cleared.status).toBe(200);
    expect(await (await app.request('/v1/courses', { headers: headers(owner.accessToken) })).json())
      .toEqual({ courses: [] });
    expect(await (await app.request('/v1/assignments', { headers: headers(owner.accessToken) })).json())
      .toMatchObject({ assignments: [{ title: '课程作业', courseId: null }] });
  });

  it('edits and deletes assignments and plans', async () => {
    const app = await testApp();
    const { accessToken } = await register(app);
    const headers = { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' };
    const assignment = await app.request('/v1/assignments', {
      method: 'POST', headers,
      body: JSON.stringify({ title: '实验报告', notes: '第一版', courseId: null, dueAt: null }),
    });
    const assignmentId = ((await assignment.json()) as { assignment: { id: string } }).assignment.id;
    const updatedAssignment = await app.request(`/v1/assignments/${assignmentId}`, {
      method: 'PUT', headers,
      body: JSON.stringify({
        title: '实验报告（终版）', notes: '已更新', courseId: null,
        dueAt: '2026-11-01T12:00:00.000Z',
      }),
    });
    expect(updatedAssignment.status).toBe(200);
    expect(await (await app.request('/v1/assignments', { headers })).json()).toMatchObject({
      assignments: [{ title: '实验报告（终版）', notes: '已更新' }],
    });
    expect((await app.request(`/v1/assignments/${assignmentId}`, {
      method: 'DELETE', headers,
    })).status).toBe(200);
    expect(await (await app.request('/v1/assignments', { headers })).json())
      .toEqual({ assignments: [] });

    const plan = await app.request('/v1/plans', {
      method: 'POST', headers,
      body: JSON.stringify({
        title: '复习', notes: '', startsAt: '2026-11-01T10:00:00.000Z',
        endsAt: '2026-11-01T11:00:00.000Z', reminderMinutes: null,
      }),
    });
    const planId = ((await plan.json()) as { plan: { id: string } }).plan.id;
    const updatedPlan = await app.request(`/v1/plans/${planId}`, {
      method: 'PUT', headers,
      body: JSON.stringify({
        title: '复习第二章', notes: '重点', startsAt: '2026-11-01T10:30:00.000Z',
        endsAt: '2026-11-01T12:00:00.000Z', reminderMinutes: 15,
      }),
    });
    expect(updatedPlan.status).toBe(200);
    expect(await (await app.request('/v1/plans', { headers })).json()).toMatchObject({
      plans: [{ title: '复习第二章', reminderMinutes: 15 }],
    });
    expect((await app.request(`/v1/plans/${planId}`, {
      method: 'DELETE', headers,
    })).status).toBe(200);
    expect(await (await app.request('/v1/plans', { headers })).json()).toEqual({ plans: [] });
  });

  it('persists a per-user semester start date and requires Monday', async () => {
    const app = await testApp();
    const student = await register(app, { username: '20260301' });
    const headers = { authorization: `Bearer ${student.accessToken}`, 'content-type': 'application/json' };
    const invalid = await app.request('/v1/me/academic-settings', {
      method: 'PUT', headers, body: JSON.stringify({ semesterStartDate: '2026-03-03' }),
    });
    expect(invalid.status).toBe(400);

    const saved = await app.request('/v1/me/academic-settings', {
      method: 'PUT', headers, body: JSON.stringify({ semesterStartDate: '2026-03-02' }),
    });
    expect(saved.status).toBe(200);
    const loaded = await app.request('/v1/me/academic-settings', {
      headers: { authorization: `Bearer ${student.accessToken}` },
    });
    expect(await loaded.json()).toEqual({ semesterStartDate: '2026-03-02' });
  });

  it('creates, lists, and completes a custom plan with a reminder', async () => {
    const app = await testApp();
    const { accessToken } = await register(app);
    const headers = { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' };
    const created = await app.request('/v1/plans', {
      method: 'POST', headers,
      body: JSON.stringify({
        title: '复习计算机网络', notes: '第三章',
        startsAt: '2026-10-08T12:00:00.000Z', endsAt: '2026-10-08T14:00:00.000Z',
        reminderMinutes: 30,
      }),
    });
    expect(created.status).toBe(201);
    const { plan } = await created.json() as { plan: { id: string } };

    const completion = await app.request(`/v1/plans/${plan.id}/completion`, {
      method: 'PATCH', headers, body: JSON.stringify({ completed: true }),
    });
    expect(completion.status).toBe(200);
    const listed = await app.request('/v1/plans', { headers });
    expect(await listed.json()).toMatchObject({
      plans: [{ title: '复习计算机网络', reminderMinutes: 30, completedAt: expect.any(String) }],
    });
  });

  it('saves user tags and discovers only opted-in users with public tags', async () => {
    const app = await testApp();
    const first = await register(app, { username: '20260001', displayName: '甲同学' });
    const second = await register(app, { username: '20260002', displayName: '乙同学' });
    const third = await register(app, { username: '20260003', displayName: '隐藏同学' });
    const jsonHeaders = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });

    await app.request('/v1/me/tags', {
      method: 'PUT',
      headers: jsonHeaders(first.accessToken),
      body: JSON.stringify({
        tags: [{ tagId: 'field-ai', isCore: true, visible: true, usedForRecommendation: true }],
      }),
    });
    await app.request('/v1/me/tags', {
      method: 'PUT',
      headers: jsonHeaders(second.accessToken),
      body: JSON.stringify({
        tags: [
          { tagId: 'field-ai', isCore: true, visible: true, usedForRecommendation: true },
          { tagId: 'goal-project', isCore: false, visible: false, usedForRecommendation: true },
        ],
      }),
    });
    for (const user of [second, third]) {
      await app.request('/v1/me', {
        method: 'PATCH',
        headers: jsonHeaders(user.accessToken),
        body: JSON.stringify({
          displayName: user === second ? '乙同学' : '隐藏同学',
          bio: '一起学习',
          departmentId: 'computer',
          discoverable: user === second,
          scheduleVisibility: 'busy_only',
        }),
      });
    }

    const ownTags = await app.request('/v1/me/tags', {
      headers: jsonHeaders(second.accessToken),
    });
    expect(await ownTags.json()).toMatchObject({
      tags: [
        { id: 'field-ai', isCore: true, visible: true, usedForRecommendation: true },
        { id: 'goal-project', visible: false },
      ],
    });

    const discovered = await app.request('/v1/discover', {
      headers: jsonHeaders(first.accessToken),
    });
    expect(discovered.status).toBe(200);
    expect(await discovered.json()).toEqual({
      users: [{
        id: expect.any(String),
        displayName: '乙同学',
        departmentId: 'computer',
        bio: '一起学习',
        sameDepartment: true,
        commonTagCount: 1,
        relationship: 'none',
        tags: [{
          id: 'field-ai', category: 'field', name: '人工智能', isCore: true, common: true,
        }],
      }],
    });
  });

  it('sends, accepts, and lists friend requests without duplicates', async () => {
    const app = await testApp();
    const first = await register(app, { username: '20260001', displayName: '甲同学' });
    const second = await register(app, { username: '20260002', displayName: '乙同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    await app.request('/v1/me', {
      method: 'PATCH',
      headers: headers(second.accessToken),
      body: JSON.stringify({
        displayName: '乙同学', bio: '学习搭子', departmentId: 'computer',
        discoverable: true, scheduleVisibility: 'busy_only',
      }),
    });
    const discovered = await app.request('/v1/discover', {
      headers: headers(first.accessToken),
    });
    const discoveredBody = await discovered.json() as {
      users: Array<{ id: string; relationship: string }>;
    };
    const target = discoveredBody.users[0];
    expect(target.relationship).toBe('none');

    const sent = await app.request('/v1/friend-requests', {
      method: 'POST',
      headers: headers(first.accessToken),
      body: JSON.stringify({ targetUserId: target.id }),
    });
    expect(sent.status).toBe(201);
    const notificationHeaders = headers(second.accessToken);
    const notificationList = await app.request('/v1/notifications', {
      headers: notificationHeaders,
    });
    const notificationBody = await notificationList.json() as {
      unreadCount: number;
      notifications: Array<{ id: string; kind: string; title: string; body: string; readAt: string | null }>;
    };
    expect(notificationBody).toMatchObject({
      unreadCount: 1,
      notifications: [{
        kind: 'friend_request',
        title: '收到好友申请',
        body: '甲同学向你发送了好友申请',
        readAt: null,
      }],
    });
    const notificationId = notificationBody.notifications[0]!.id;
    const wrongOwnerMark = await app.request('/v1/notifications/read', {
      method: 'POST',
      headers: headers(first.accessToken),
      body: JSON.stringify({ id: notificationId }),
    });
    expect(await wrongOwnerMark.json()).toMatchObject({ unreadCount: 0 });
    expect((await app.request('/v1/notifications', {
      headers: notificationHeaders,
    }).then((response) => response.json()))).toMatchObject({ unreadCount: 1 });
    const marked = await app.request('/v1/notifications/read', {
      method: 'POST',
      headers: notificationHeaders,
      body: JSON.stringify({ id: notificationId }),
    });
    expect(await marked.json()).toMatchObject({ unreadCount: 0 });

    const duplicate = await app.request('/v1/friend-requests', {
      method: 'POST',
      headers: headers(first.accessToken),
      body: JSON.stringify({ targetUserId: target.id }),
    });
    expect(duplicate.status).toBe(409);

    const secondList = await app.request('/v1/friends', {
      headers: headers(second.accessToken),
    });
    const secondBody = await secondList.json() as {
      incoming: Array<{ id: string; displayName: string }>;
    };
    expect(secondBody.incoming).toMatchObject([{ displayName: '甲同学' }]);
    const accepted = await app.request(
      `/v1/friend-requests/${secondBody.incoming[0].id}`,
      {
        method: 'PATCH',
        headers: headers(second.accessToken),
        body: JSON.stringify({ action: 'accept' }),
      },
    );
    expect(accepted.status).toBe(200);

    const firstList = await app.request('/v1/friends', {
      headers: headers(first.accessToken),
    });
    expect(await firstList.json()).toMatchObject({
      friends: [{ displayName: '乙同学', bio: '学习搭子' }],
      incoming: [],
      outgoing: [],
    });
    const afterAccept = await app.request('/v1/discover', {
      headers: headers(first.accessToken),
    });
    expect(await afterAccept.json()).toMatchObject({
      users: [{ displayName: '乙同学', relationship: 'friends' }],
    });
  });

  it('computes shared free time and processes an availability invite', async () => {
    const app = await testApp();
    const first = await register(app, { username: '20260001', displayName: '甲同学' });
    const second = await register(app, { username: '20260002', displayName: '乙同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    await app.request('/v1/me', {
      method: 'PATCH', headers: headers(second.accessToken),
      body: JSON.stringify({
        displayName: '乙同学', bio: '', departmentId: 'computer',
        discoverable: true, scheduleVisibility: 'busy_only',
      }),
    });
    const discovered = await app.request('/v1/discover', { headers: headers(first.accessToken) });
    const friendId = ((await discovered.json()) as { users: Array<{ id: string }> }).users[0].id;
    const sent = await app.request('/v1/friend-requests', {
      method: 'POST', headers: headers(first.accessToken),
      body: JSON.stringify({ targetUserId: friendId }),
    });
    const requestId = ((await sent.json()) as { request: { id: string } }).request.id;
    await app.request(`/v1/friend-requests/${requestId}`, {
      method: 'PATCH', headers: headers(second.accessToken),
      body: JSON.stringify({ action: 'accept' }),
    });

    await app.request('/v1/courses', {
      method: 'POST', headers: headers(first.accessToken),
      body: JSON.stringify({
        name: '早课', teacher: null, color: '#3366FF',
        meetings: [{
          weekday: 1, startMinute: 480, endMinute: 570,
          startWeek: 1, endWeek: 16, weekParity: 'odd',
          campus: null, building: null, room: null,
        }],
      }),
    });
    await app.request('/v1/plans', {
      method: 'POST', headers: headers(second.accessToken),
      body: JSON.stringify({
        title: '个人安排', notes: '', startsAt: '2026-10-12T10:00:00.000Z',
        endsAt: '2026-10-12T11:00:00.000Z', reminderMinutes: null,
      }),
    });
    const availability = await app.request(
      `/v1/availability?friendId=${friendId}&date=2026-10-12&weekNumber=3&dayStartMinute=480&dayEndMinute=1320&timezoneOffsetMinutes=0`,
      { headers: headers(first.accessToken) },
    );
    expect(availability.status).toBe(200);
    expect(await availability.json()).toEqual({
      date: '2026-10-12', weekNumber: 3,
      freeSlots: [
        { startMinute: 570, endMinute: 600 },
        { startMinute: 660, endMinute: 1320 },
      ],
      friendBlocks: [],
    });

    const invited = await app.request('/v1/availability-invites', {
      method: 'POST', headers: headers(first.accessToken),
      body: JSON.stringify({
        friendId, title: '一起午餐',
        startsAt: '2026-10-12T11:00:00.000Z',
        endsAt: '2026-10-12T12:00:00.000Z',
      }),
    });
    expect(invited.status).toBe(201);
    const inviteId = ((await invited.json()) as { invite: { id: string } }).invite.id;
    const incoming = await app.request('/v1/availability-invites', {
      headers: headers(second.accessToken),
    });
    expect(await incoming.json()).toMatchObject({
      invites: [{ id: inviteId, direction: 'incoming', title: '一起午餐', status: 'pending' }],
    });
    const accepted = await app.request(`/v1/availability-invites/${inviteId}`, {
      method: 'PATCH', headers: headers(second.accessToken),
      body: JSON.stringify({ action: 'accept' }),
    });
    expect(accepted.status).toBe(200);
    const outgoing = await app.request('/v1/availability-invites', {
      headers: headers(first.accessToken),
    });
    expect(await outgoing.json()).toMatchObject({
      invites: [{ id: inviteId, direction: 'outgoing', status: 'accepted' }],
    });
  });

  it('publishes a tagged project and accepts a join application', async () => {
    const app = await testApp();
    const owner = await register(app, { username: '20260001', displayName: '项目负责人' });
    const applicant = await register(app, { username: '20260002', displayName: '申请同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    const created = await app.request('/v1/projects', {
      method: 'POST', headers: headers(owner.accessToken),
      body: JSON.stringify({
        title: '校园课表助手',
        description: '<b>寻找后端同学</b>',
        capacity: 3,
        tagIds: ['field-backend', 'goal-project'],
      }),
    });
    expect(created.status).toBe(201);
    const projectId = ((await created.json()) as { project: { id: string } }).project.id;

    const listed = await app.request('/v1/projects?status=recruiting&tagId=field-backend', {
      headers: headers(applicant.accessToken),
    });
    expect(await listed.json()).toMatchObject({
      projects: [{
        id: projectId,
        title: '校园课表助手',
        description: '<b>寻找后端同学</b>',
        ownerName: '项目负责人',
        memberCount: 1,
        capacity: 3,
        ownedByMe: false,
        myApplicationStatus: null,
        tags: [{ id: 'field-backend' }, { id: 'goal-project' }],
      }],
    });

    const applied = await app.request(`/v1/projects/${projectId}/applications`, {
      method: 'POST', headers: headers(applicant.accessToken),
      body: JSON.stringify({ message: '我熟悉 Hono 和 SQLite' }),
    });
    expect(applied.status).toBe(201);
    const applicationId = ((await applied.json()) as { application: { id: string } }).application.id;
    const duplicate = await app.request(`/v1/projects/${projectId}/applications`, {
      method: 'POST', headers: headers(applicant.accessToken),
      body: JSON.stringify({ message: '重复申请' }),
    });
    expect(duplicate.status).toBe(409);

    const ownerApplications = await app.request('/v1/project-applications', {
      headers: headers(owner.accessToken),
    });
    expect(await ownerApplications.json()).toMatchObject({
      applications: [{
        id: applicationId,
        direction: 'incoming',
        applicantName: '申请同学',
        status: 'pending',
      }],
    });
    const accepted = await app.request(`/v1/project-applications/${applicationId}`, {
      method: 'PATCH', headers: headers(owner.accessToken),
      body: JSON.stringify({ action: 'accept' }),
    });
    expect(accepted.status).toBe(200);
    const afterAccept = await app.request('/v1/projects', {
      headers: headers(owner.accessToken),
    });
    expect(await afterAccept.json()).toMatchObject({
      projects: [{ id: projectId, memberCount: 2 }],
    });
  });

  it('does not overfill a project when applications are accepted concurrently', async () => {
    const app = await testApp();
    const owner = await register(app, { username: '20260101', displayName: '负责人' });
    const first = await register(app, { username: '20260102', displayName: '甲同学' });
    const second = await register(app, { username: '20260103', displayName: '乙同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    const created = await app.request('/v1/projects', {
      method: 'POST', headers: headers(owner.accessToken),
      body: JSON.stringify({
        title: '双人项目', description: '只剩一个位置', capacity: 2, tagIds: [],
      }),
    });
    const projectId = ((await created.json()) as { project: { id: string } }).project.id;
    const applicationIds = await Promise.all([first, second].map(async (applicant) => {
      const response = await app.request(`/v1/projects/${projectId}/applications`, {
        method: 'POST', headers: headers(applicant.accessToken),
        body: JSON.stringify({ message: '申请加入' }),
      });
      return ((await response.json()) as { application: { id: string } }).application.id;
    }));

    const responses = await Promise.all(applicationIds.map((id) => app.request(
      `/v1/project-applications/${id}`,
      {
        method: 'PATCH', headers: headers(owner.accessToken),
        body: JSON.stringify({ action: 'accept' }),
      },
    )));
    expect(responses.map((response) => response.status).sort()).toEqual([200, 409]);
    const projects = await app.request('/v1/projects', { headers: headers(owner.accessToken) });
    expect(await projects.json()).toMatchObject({
      projects: [{ id: projectId, memberCount: 2 }],
    });
  });

  it('publishes, filters, and publicly replies to a forum post', async () => {
    const app = await testApp();
    const author = await register(app, { username: '20260201', displayName: '发帖同学' });
    const respondent = await register(app, { username: '20260202', displayName: '回复同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });
    const created = await app.request('/v1/forum/posts', {
      method: 'POST', headers: headers(author.accessToken),
      body: JSON.stringify({
        category: 'course', title: '高数复习建议', body: '<b>应该先看哪一章？</b>',
      }),
    });
    expect(created.status).toBe(201);
    const postId = ((await created.json()) as { post: { id: string } }).post.id;

    const filtered = await app.request('/v1/forum/posts?category=course', {
      headers: headers(respondent.accessToken),
    });
    expect(await filtered.json()).toMatchObject({
      posts: [{
        id: postId,
        authorName: '发帖同学',
        category: 'course',
        title: '高数复习建议',
        body: '<b>应该先看哪一章？</b>',
        replyCount: 0,
      }],
    });
    const replied = await app.request(`/v1/forum/posts/${postId}/replies`, {
      method: 'POST', headers: headers(respondent.accessToken),
      body: JSON.stringify({ body: '建议先复习极限。' }),
    });
    expect(replied.status).toBe(201);

    const detail = await app.request(`/v1/forum/posts/${postId}`, {
      headers: headers(author.accessToken),
    });
    expect(await detail.json()).toMatchObject({
      post: { id: postId, replyCount: 1 },
      replies: [{ authorName: '回复同学', body: '建议先复习极限。' }],
    });
  });

  it('keeps admin authentication separate from students and enforces moderation with audit logging', async () => {
    const app = await testApp();
    const student = await register(app, { username: '20260211' });
    const studentAdminAttempt = await app.request('/v1/admin/overview', {
      headers: { authorization: `Bearer ${student.accessToken}` },
    });
    expect(studentAdminAttempt.status).toBe(401);

    const login = await app.request('/v1/admin/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    expect(login.status).toBe(200);
    const adminToken = ((await login.json()) as { accessToken: string }).accessToken;
    const adminHeaders = { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json' };
    const created = await app.request('/v1/forum/posts', {
      method: 'POST',
      headers: { authorization: `Bearer ${student.accessToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ category: 'campus', title: '测试帖子', body: '仅管理员可以隐藏这条帖子。' }),
    });
    const postId = ((await created.json()) as { post: { id: string } }).post.id;
    const hidden = await app.request(`/v1/admin/content/forum_post/${postId}`, {
      method: 'PATCH', headers: adminHeaders, body: JSON.stringify({ action: 'hide' }),
    });
    expect(hidden.status).toBe(200);
    const listing = await app.request('/v1/forum/posts', {
      headers: { authorization: `Bearer ${student.accessToken}` },
    });
    expect(await listing.json()).toMatchObject({ posts: [] });

    const audit = await app.request('/v1/admin/audit', { headers: adminHeaders });
    expect(await audit.json()).toMatchObject({
      entries: [{ actor: 'operator', action: 'content.hide', entityType: 'forum_post', entityId: postId }],
    });
    const logout = await app.request('/v1/admin/auth/logout', { method: 'POST', headers: adminHeaders });
    expect(logout.status).toBe(200);
    const revoked = await app.request('/v1/admin/overview', {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    expect(revoked.status).toBe(401);
  });

  it('accepts a content report and lets the admin resolve it', async () => {
    const app = await testApp();
    const student = await register(app, { username: '20260221' });
    const headers = { authorization: `Bearer ${student.accessToken}`, 'content-type': 'application/json' };
    const post = await app.request('/v1/forum/posts', {
      method: 'POST', headers,
      body: JSON.stringify({ category: 'general', title: '需要审核', body: '举报流程测试正文。' }),
    });
    const postId = ((await post.json()) as { post: { id: string } }).post.id;
    const reported = await app.request('/v1/reports', {
      method: 'POST', headers,
      body: JSON.stringify({ targetType: 'forum_post', targetId: postId, reason: '测试举报内容有问题' }),
    });
    expect(reported.status).toBe(201);
    const reportId = ((await reported.json()) as { report: { id: string } }).report.id;
    const login = await app.request('/v1/admin/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    const token = ((await login.json()) as { accessToken: string }).accessToken;
    const resolved = await app.request(`/v1/admin/reports/${reportId}`, {
      method: 'PATCH',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ status: 'resolved' }),
    });
    expect(resolved.status).toBe(200);
  });

  it('suspending a user revokes active sessions and removes the user from recommendations', async () => {
    const app = await testApp();
    const student = await register(app, { username: '20260231', displayName: '待封禁同学' });
    const adminLogin = await app.request('/v1/admin/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    const adminToken = ((await adminLogin.json()) as { accessToken: string }).accessToken;
    const suspended = await app.request(`/v1/admin/users/${student.user.id}/status`, {
      method: 'PATCH',
      headers: { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ status: 'suspended' }),
    });
    expect(suspended.status).toBe(200);
    const revoked = await app.request('/v1/me', { headers: { authorization: `Bearer ${student.accessToken}` } });
    expect(revoked.status).toBe(401);
  });

  it('creates global user tags, reuses duplicates, and applies them to a profile', async () => {
    const app = await testApp();
    const student = await register(app, { username: 'tagmaker', displayName: '标签同学' });
    const headers = (token: string) => ({
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    });

    const unauthorized = await app.request('/v1/tags', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: '校园摄影', category: 'interest' }),
    });
    expect(unauthorized.status).toBe(401);

    const created = await app.request('/v1/tags', {
      method: 'POST',
      headers: headers(student.accessToken),
      body: JSON.stringify({ name: ' 校园  摄影 ', category: 'interest' }),
    });
    expect(created.status).toBe(201);
    const createdTag = ((await created.json()) as { tag: { id: string; name: string; category: string } }).tag;
    expect(createdTag).toMatchObject({ name: '校园 摄影', category: 'interest' });

    const duplicate = await app.request('/v1/tags', {
      method: 'POST',
      headers: headers(student.accessToken),
      body: JSON.stringify({ name: '校园 摄影', category: 'interest' }),
    });
    expect(duplicate.status).toBe(200);
    expect(((await duplicate.json()) as { tag: { id: string } }).tag.id).toBe(createdTag.id);

    const otherCategory = await app.request('/v1/tags', {
      method: 'POST',
      headers: headers(student.accessToken),
      body: JSON.stringify({ name: '校园 摄影', category: 'field' }),
    });
    expect(otherCategory.status).toBe(201);
    expect(((await otherCategory.json()) as { tag: { id: string } }).tag.id).not.toBe(createdTag.id);

    const invalid = await app.request('/v1/tags', {
      method: 'POST',
      headers: headers(student.accessToken),
      body: JSON.stringify({ name: '无效分类', category: 'unknown' }),
    });
    expect(invalid.status).toBe(400);

    const applied = await app.request('/v1/me/tags', {
      method: 'PUT',
      headers: headers(student.accessToken),
      body: JSON.stringify({
        tags: [{ tagId: createdTag.id, isCore: false, visible: true, usedForRecommendation: true }],
      }),
    });
    expect(applied.status).toBe(200);
    const ownTags = await app.request('/v1/me/tags', { headers: headers(student.accessToken) });
    expect((await ownTags.json() as { tags: Array<{ id: string }> }).tags.map((tag) => tag.id)).toContain(createdTag.id);

    const catalog = await app.request('/v1/tags', { headers: headers(student.accessToken) });
    expect((await catalog.json() as { tags: Array<{ id: string }> }).tags.map((tag) => tag.id)).toContain(createdTag.id);
  });

  it('creates a controlled tag, applies tag updates, and records audit entries', async () => {
    const app = await testApp();
    const login = await app.request('/v1/admin/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    const token = ((await login.json()) as { accessToken: string }).accessToken;
    const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
    const created = await app.request('/v1/admin/tags', {
      method: 'POST', headers,
      body: JSON.stringify({ category: 'field', name: '数据可视化', active: true }),
    });
    expect(created.status).toBe(200);
    const tagId = ((await created.json()) as { tag: { id: string } }).tag.id;
    const disabled = await app.request('/v1/admin/tags', {
      method: 'POST', headers,
      body: JSON.stringify({ id: tagId, category: 'field', name: '数据可视化', active: false }),
    });
    expect(disabled.status).toBe(200);
    const student = await register(app);
    const publicTags = await app.request('/v1/tags', { headers: { authorization: `Bearer ${student.accessToken}` } });
    expect((await publicTags.json() as { tags: Array<{ id: string }> }).tags.map((tag) => tag.id)).not.toContain(tagId);
    const audit = await app.request('/v1/admin/audit', { headers });
    const auditEntries = (await audit.json() as { entries: Array<{ action: string; entityId: string }> }).entries;
    expect(auditEntries.some((entry) => entry.action === 'tag.update' && entry.entityId === tagId)).toBe(true);
    expect(auditEntries.some((entry) => entry.action === 'tag.create' && entry.entityId === tagId)).toBe(true);
  });
  it('reveals a friend busy blocks only as far as their schedule visibility allows', async () => {
    const app = await testApp();
    const first = await register(app, { username: '20260001', displayName: '甲同学' });
    const second = await register(app, { username: '20260002', displayName: '乙同学' });
    const headers = (token: string) => ({ authorization: `Bearer ${token}`, 'content-type': 'application/json' });
    await app.request('/v1/me', {
      method: 'PATCH', headers: headers(second.accessToken),
      body: JSON.stringify({ displayName: '乙同学', bio: '', departmentId: 'computer', discoverable: true, scheduleVisibility: 'busy_only' }),
    });
    const friendId = second.user.id;
    const sent = await app.request('/v1/friend-requests', {
      method: 'POST', headers: headers(first.accessToken), body: JSON.stringify({ targetUserId: friendId }),
    });
    const requestId = ((await sent.json()) as { request: { id: string } }).request.id;
    await app.request(`/v1/friend-requests/${requestId}`, {
      method: 'PATCH', headers: headers(second.accessToken), body: JSON.stringify({ action: 'accept' }),
    });
    await app.request('/v1/courses', {
      method: 'POST', headers: headers(second.accessToken),
      body: JSON.stringify({
        name: '线性代数', teacher: null, color: '#3366FF',
        meetings: [{ weekday: 1, startMinute: 600, endMinute: 660, startWeek: 1, endWeek: 16, weekParity: 'all', campus: null, building: null, room: null }],
      }),
    });
    await app.request('/v1/plans', {
      method: 'POST', headers: headers(second.accessToken),
      body: JSON.stringify({
        title: '社团例会', notes: '只给自己看的备注', startsAt: '2026-10-12T13:00:00.000Z',
        endsAt: '2026-10-12T14:00:00.000Z', reminderMinutes: null,
      }),
    });
    const query = `/v1/availability?friendId=${friendId}&date=2026-10-12&weekNumber=3&dayStartMinute=480&dayEndMinute=1320&timezoneOffsetMinutes=0`;
    const setVisibility = (value: string) => app.request('/v1/me', {
      method: 'PATCH', headers: headers(second.accessToken),
      body: JSON.stringify({ displayName: '乙同学', bio: '', departmentId: 'computer', discoverable: true, scheduleVisibility: value }),
    });

    expect(await (await app.request(query, { headers: headers(first.accessToken) })).json()).toMatchObject({ friendBlocks: [] });

    await setVisibility('course_name');
    const courseName = await (await app.request(query, { headers: headers(first.accessToken) })).json() as {
      friendBlocks: Array<{ title: string | null; kind: string }>; freeSlots: unknown; };
    expect(courseName.friendBlocks).toEqual([
      { startMinute: 600, endMinute: 660, kind: 'course', title: '线性代数' },
      { startMinute: 780, endMinute: 840, kind: 'plan', title: null },
    ]);
    expect(JSON.stringify(courseName)).not.toContain('社团例会');
    expect(JSON.stringify(courseName)).not.toContain('只给自己看的备注');

    await setVisibility('full');
    const full = await (await app.request(query, { headers: headers(first.accessToken) })).json() as { friendBlocks: unknown };
    expect(JSON.stringify(full)).toContain('社团例会');
    expect(JSON.stringify(full)).not.toContain('只给自己看的备注');
  });

  it('does not enforce the legacy student identity expiry timestamp', async () => {
    const app = await testApp();
    const student = await register(app, { username: '20260001', displayName: '内测同学' });
    const viewer = await register(app, { username: '20260002', displayName: '查看者' });
    await app.request('/v1/me', {
      method: 'PATCH', headers: { authorization: `Bearer ${student.accessToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ displayName: '内测同学', bio: '', departmentId: 'computer', discoverable: true, scheduleVisibility: 'busy_only' }),
    });
    await latestDatabase.execute({
      sql: 'UPDATE student_identities SET expires_at = ? WHERE user_id = ?',
      params: ['2020-01-01T00:00:00.000Z', student.user.id],
    });

    const profile = await app.request('/v1/me', { headers: { authorization: `Bearer ${student.accessToken}` } });
    expect(profile.status).toBe(200);
    const login = await app.request('/v1/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: '20260001', appPassword: 'correct-horse-battery' }),
    });
    expect(login.status).toBe(200);
    const discovered = await app.request('/v1/discover', { headers: { authorization: `Bearer ${viewer.accessToken}` } });
    expect(((await discovered.json()) as { users: Array<{ id: string }> }).users.map((user) => user.id)).toContain(student.user.id);
  });

  it('issues at most five invite codes per user per month and never shows issued codes again', async () => {
    const app = await testApp();
    const inviter = await register(app, { username: '20260001' });
    const headers = { authorization: `Bearer ${inviter.accessToken}` };
    const codes: string[] = [];
    for (let index = 0; index < 5; index += 1) {
      const issued = await app.request('/v1/me/invites', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: '{}' });
      expect(issued.status).toBe(201);
      codes.push(((await issued.json()) as { code: string }).code);
    }
    expect(new Set(codes).size).toBe(5);
    const exceeded = await app.request('/v1/me/invites', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: '{}' });
    expect(exceeded.status).toBe(429);
    expect(await exceeded.json()).toMatchObject({ error: { code: 'invite_quota_exceeded' } });
    const listed = await (await app.request('/v1/me/invites', { headers })).json() as {
      remainingThisMonth: number; invites: unknown[];
    };
    expect(listed.remainingThisMonth).toBe(0);
    expect(listed.invites).toHaveLength(5);
    expect(JSON.stringify(listed)).not.toContain(codes[0]!);
  });

  it('resets the invite quota at the start of each calendar month in Asia/Shanghai', async () => {
    let now = new Date('2026-10-31T10:00:00.000Z');
    const app = await testApp({ clock: () => now });
    const inviter = await register(app, { username: '20260001' });
    const headers = { authorization: `Bearer ${inviter.accessToken}` };
    for (let index = 0; index < 5; index += 1) {
      expect((await app.request('/v1/me/invites', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: '{}' })).status).toBe(201);
    }
    expect((await app.request('/v1/me/invites', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: '{}' })).status).toBe(429);
    now = new Date('2026-10-31T16:30:00.000Z');
    expect((await app.request('/v1/me/invites', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: '{}' })).status).toBe(201);
  });

  it('rejects reused, unknown, and duplicate-email registrations', async () => {
    const app = await testApp();
    const code = invitePool[0]!;
    const request = (body: Record<string, string>) => app.request('/v1/auth/register', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: '20260001', email: 'a@example.edu', appPassword: 'correct-horse-battery',
        displayName: '同学', departmentId: null, inviteCode: code, ...body,
      }),
    });
    expect((await request({})).status).toBe(201);

    const reused = await request({ username: '20260002', email: 'b@example.edu' });
    expect(reused.status).toBe(403);
    expect(await reused.json()).toMatchObject({ error: { code: 'invalid_invite_code' } });

    const unknown = await request({ username: '20260003', email: 'c@example.edu', inviteCode: 'NOTAREALCODE1' });
    expect(unknown.status).toBe(403);

    const duplicateEmail = await request({ username: '20260004', email: 'A@example.edu', inviteCode: invitePool[1]! });
    expect(duplicateEmail.status).toBe(409);
    expect(await duplicateEmail.json()).toMatchObject({ error: { code: 'email_already_registered' } });

    const badEmail = await request({ username: '20260005', email: 'not-an-email', inviteCode: invitePool[2]! });
    expect(badEmail.status).toBe(400);
  });

  it('accepts invite codes typed in lowercase without dashes', async () => {
    const app = await testApp();
    const typed = invitePool[3]!.toLowerCase().replace(/-/g, '');
    const registration = await register(app, { username: '20260001', inviteCode: typed });
    expect(registration.accessToken).toBeTruthy();
  });

  it('refuses registration when invite registration is closed by configuration', async () => {
    const app = await testApp({ inviteRegistrationEnabled: false });
    const closed = await app.request('/v1/auth/register', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: '20260001', email: 'a@example.edu', appPassword: 'correct-horse-battery',
        displayName: '同学', departmentId: null, inviteCode: invitePool[0],
      }),
    });
    expect(closed.status).toBe(403);
    expect(await closed.json()).toMatchObject({ error: { code: 'registration_closed' } });
  });

  it('lets operators issue invite codes that do not count against any user quota', async () => {
    const app = await testApp();
    const login = await app.request('/v1/admin/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    const adminHeaders = { authorization: `Bearer ${((await login.json()) as { accessToken: string }).accessToken}` };
    const issued = await app.request('/v1/admin/invites', { method: 'POST', headers: { ...adminHeaders, 'content-type': 'application/json' }, body: '{}' });
    expect(issued.status).toBe(201);
    const { code } = await issued.json() as { code: string };
    const registration = await register(app, { username: '20260001', inviteCode: code });
    const quota = await (await app.request('/v1/me/invites', {
      headers: { authorization: `Bearer ${registration.accessToken}` },
    })).json() as { remainingThisMonth: number };
    expect(quota.remainingThisMonth).toBe(5);
  });

  it('requires JSON content type for bodyless admin POSTs and logout', async () => {
    const app = await testApp();
    const login = await app.request('/v1/admin/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: 'operator', password: 'a-very-long-test-admin-password' }),
    });
    const adminHeaders = { authorization: `Bearer ${((await login.json()) as { accessToken: string }).accessToken}` };

    const missingContentType = await app.request('/v1/admin/invites', {
      method: 'POST',
      headers: adminHeaders,
    });
    expect(missingContentType.status).toBe(415);
    expect(await missingContentType.json()).toMatchObject({
      error: { code: 'unsupported_media_type', message: '请求必须使用 application/json' },
    });

    const issued = await app.request('/v1/admin/invites', {
      method: 'POST',
      headers: { ...adminHeaders, 'content-type': 'application/json' },
    });
    expect(issued.status).toBe(201);

    const logout = await app.request('/v1/admin/auth/logout', {
      method: 'POST',
      headers: { ...adminHeaders, 'content-type': 'application/json' },
    });
    expect(logout.status).toBe(200);
  });
});
