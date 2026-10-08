import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { NodeSqliteDatabase } from '../src/adapters/node-database.js';
import { DevelopmentStudentVerifier } from '../src/adapters/student-verifier.js';
import { createApp } from '../src/http/app.js';

function testApp() {
  const database = new NodeSqliteDatabase(':memory:');
  database.applyMigration(readFileSync(new URL('../migrations/0001_initial.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0002_plans.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0003_friends.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0004_availability.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0005_auth_throttles.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0006_projects.sql', import.meta.url), 'utf8'));
  database.applyMigration(readFileSync(new URL('../migrations/0007_forum.sql', import.meta.url), 'utf8'));
  return createApp({
    database,
    studentVerifier: new DevelopmentStudentVerifier(),
    studentIdPepper: 'test-pepper',
    allowedOrigins: ['http://127.0.0.1:8080'],
  });
}

async function register(
  app: ReturnType<typeof createApp>,
  input: { studentId?: string; displayName?: string; departmentId?: string } = {},
) {
  const response = await app.request('/v1/auth/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      studentId: input.studentId ?? '20260001',
      schoolPassword: 'dev-password',
      appPassword: 'correct-horse-battery',
      displayName: input.displayName ?? '测试同学',
      departmentId: input.departmentId ?? 'computer',
    }),
  });
  expect(response.status).toBe(201);
  return (await response.json()) as { accessToken: string };
}

describe('FStudy API', () => {
  it('applies API security headers and restricts browser origins', async () => {
    const app = testApp();
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
    const app = testApp();
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
      body: JSON.stringify({ studentId: '20260001', appPassword: 'x'.repeat(70_000) }),
    });
    expect(oversized.status).toBe(413);
    expect(await oversized.json()).toEqual({
      error: { code: 'request_too_large', message: '请求体过大' },
    });
  });

  it('rejects malformed bearer tokens before session lookup', async () => {
    const app = testApp();
    const response = await app.request('/v1/me', {
      headers: { authorization: `Bearer ${'x'.repeat(5000)}` },
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      error: { code: 'authentication_required', message: '需要登录' },
    });
  });

  it('registers and authenticates a development student without retaining the school password', async () => {
    const app = testApp();
    const registration = await register(app);
    const profile = await app.request('/v1/me', {
      headers: { authorization: `Bearer ${registration.accessToken}` },
    });
    expect(profile.status).toBe(200);
    expect(await profile.json()).toMatchObject({
      user: { displayName: '测试同学', departmentId: 'computer', discoverable: false },
    });

    const duplicate = await app.request('/v1/auth/register', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        studentId: '20260001', schoolPassword: 'dev-password', appPassword: 'another-password',
        displayName: '另一个账户', departmentId: 'computer',
      }),
    });
    expect(duplicate.status).toBe(409);
  });

  it('rate limits repeated login failures and revokes logout sessions', async () => {
    const app = testApp();
    const { accessToken } = await register(app);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const failed = await app.request('/v1/auth/login', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ studentId: '20260001', appPassword: 'wrong-password' }),
      });
      expect(failed.status).toBe(401);
    }
    const blocked = await app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ studentId: '20260001', appPassword: 'correct-horse-battery' }),
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
    const app = testApp();
    await register(app);
    const attempt = (studentId: string) => app.request('/v1/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ studentId, appPassword: 'wrong-password' }),
    });
    const unknown = await attempt('20269999');
    const existing = await attempt('20260001');
    expect(unknown.status).toBe(401);
    expect(existing.status).toBe(401);
    expect(await unknown.json()).toEqual(await existing.json());
  });

  it('creates and lists a manually entered course', async () => {
    const app = testApp();
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

  it('creates, lists, and completes a custom plan with a reminder', async () => {
    const app = testApp();
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
    const app = testApp();
    const first = await register(app, { studentId: '20260001', displayName: '甲同学' });
    const second = await register(app, { studentId: '20260002', displayName: '乙同学' });
    const third = await register(app, { studentId: '20260003', displayName: '隐藏同学' });
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
    const app = testApp();
    const first = await register(app, { studentId: '20260001', displayName: '甲同学' });
    const second = await register(app, { studentId: '20260002', displayName: '乙同学' });
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
    const app = testApp();
    const first = await register(app, { studentId: '20260001', displayName: '甲同学' });
    const second = await register(app, { studentId: '20260002', displayName: '乙同学' });
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
    const app = testApp();
    const owner = await register(app, { studentId: '20260001', displayName: '项目负责人' });
    const applicant = await register(app, { studentId: '20260002', displayName: '申请同学' });
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
    const app = testApp();
    const owner = await register(app, { studentId: '20260101', displayName: '负责人' });
    const first = await register(app, { studentId: '20260102', displayName: '甲同学' });
    const second = await register(app, { studentId: '20260103', displayName: '乙同学' });
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
    const app = testApp();
    const author = await register(app, { studentId: '20260201', displayName: '发帖同学' });
    const respondent = await register(app, { studentId: '20260202', displayName: '回复同学' });
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
});
