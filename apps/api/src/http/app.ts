import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { bodyLimit } from 'hono/body-limit';
import { secureHeaders } from 'hono/secure-headers';
import { DomainError } from '../core/errors.js';
import type { RuntimeDependencies } from '../core/types.js';
import { AssignmentService } from '../modules/assignments/assignment-service.js';
import { AccountService } from '../modules/identity/account-service.js';
import { ScheduleService } from '../modules/schedule/schedule-service.js';
import { TagService } from '../modules/tags/tag-service.js';
import { PlanService } from '../modules/plans/plan-service.js';
import { DiscoveryService } from '../modules/discovery/discovery-service.js';
import { FriendService } from '../modules/friends/friend-service.js';
import { AvailabilityService } from '../modules/availability/availability-service.js';
import { ProjectService } from '../modules/projects/project-service.js';
import { ForumService } from '../modules/forum/forum-service.js';
import { AdminService } from '../modules/admin/admin-service.js';
import { NotificationService } from '../modules/notifications/notification-service.js';
import { InviteService } from '../modules/invites/invite-service.js';
import { CasLoginService } from '../modules/identity/cas-login-service.js';
import { requireAdminAuthentication, requireAuthentication, type AppVariables } from './auth.js';
import {
  AssignmentSchema,
  AcademicSettingsSchema,
  AdminContentActionSchema,
  AdminLoginSchema,
  AdminPasswordSchema,
  AdminReportStatusSchema,
  AdminTagSchema,
  AdminUserStatusSchema,
  NotificationReadSchema,
  CasCompleteSchema,
  AvailabilityInviteActionSchema,
  AvailabilityInviteSchema,
  AvailabilityQuerySchema,
  CompletionSchema,
  CourseSchema,
  ContentReportSchema,
  CreateTagSchema,
  FriendRequestActionSchema,
  FriendRequestSchema,
  ForumPostSchema,
  ForumReplySchema,
  LoginSchema,
  PlanSchema,
  ProjectApplicationActionSchema,
  ProjectApplicationSchema,
  ProjectSchema,
  ProjectStatusSchema,
  ProfileSchema,
  RegisterSchema,
  UserTagsSchema,
} from './schemas.js';

const OPENAPI_DOCUMENT = {
  openapi: '3.1.0',
  info: { title: 'FStudy API', version: '0.1.0' },
  servers: [{ url: '/' }],
  paths: {
    '/v1/auth/register': { post: { summary: '使用用户名、邮箱、邀请码和本系统密码注册' } },
    '/v1/me/invites': { get: { summary: '读取本人本月邀请额度与邀请码状态' }, post: { summary: '生成一个邀请码（每人每月 5 个）' } },
    '/v1/admin/invites': { post: { summary: '生成运营邀请码（不占用个人额度）' } },
    '/v1/auth/login': { post: { summary: '使用用户名和本系统密码登录' } },
    '/v1/auth/logout': { post: { summary: '撤销当前会话并退出登录' } },
    '/v1/me': { get: { summary: '读取个人资料' }, patch: { summary: '更新个人资料和隐私偏好' } },
    '/v1/tags': {
      get: { summary: '读取全局标签（需要登录）' },
      post: { summary: '创建或复用全局标签（需要登录）' },
    },
    '/v1/me/tags': { get: { summary: '读取当前用户标签' }, put: { summary: '替换当前用户标签' } },
    '/v1/courses': { get: { summary: '读取课表' }, post: { summary: '添加课程' } },
    '/v1/me/academic-settings': { get: { summary: '读取学期设置' }, put: { summary: '设置学期第一周日期' } },
    '/v1/assignments': { get: { summary: '读取作业' }, post: { summary: '添加作业' } },
    '/v1/assignments/{id}/completion': { patch: { summary: '标记作业完成或未完成' } },
    '/v1/plans': { get: { summary: '读取自定义安排' }, post: { summary: '添加自定义安排' } },
    '/v1/plans/{id}/completion': { patch: { summary: '标记自定义安排完成或未完成' } },
    '/v1/discover': { get: { summary: '发现可推荐的同学' } },
    '/v1/friends': { get: { summary: '读取好友及请求' } },
    '/v1/friend-requests': { post: { summary: '发送好友请求' } },
    '/v1/friend-requests/{id}': { patch: { summary: '接受、拒绝或取消好友请求' } },
    '/v1/availability': { get: { summary: '查询好友共同空闲时间' } },
    '/v1/availability-invites/{id}': { patch: { summary: '接受、拒绝或取消共同空闲邀请' } },
    '/v1/availability-invites': {
      get: { summary: '读取共同空闲邀请' },
      post: { summary: '发起共同空闲邀请' },
    },
    '/v1/projects': { get: { summary: '浏览项目' }, post: { summary: '发布项目' } },
    '/v1/projects/{id}/status': { patch: { summary: '更新本人项目状态' } },
    '/v1/projects/{id}/applications': { post: { summary: '申请加入项目' } },
    '/v1/project-applications': { get: { summary: '读取项目申请' } },
    '/v1/project-applications/{id}': { patch: { summary: '处理或撤回项目申请' } },
    '/v1/forum/posts': { get: { summary: '浏览讨论帖' }, post: { summary: '发布讨论帖' } },
    '/v1/forum/posts/{id}': { get: { summary: '读取帖子和公开回复' } },
    '/v1/forum/posts/{id}/replies': { post: { summary: '公开回复帖子' } },
    '/v1/reports': { post: { summary: '举报公开内容' } },
    '/v1/notifications': { get: { summary: '读取站内通知和未读数量' } },
    '/v1/notifications/read': { post: { summary: '标记通知为已读' } },
    '/v1/auth/cas/start': { post: { summary: '发起浏览器北邮 CAS 身份认证' } },
    '/v1/auth/cas/callback': { get: { summary: '接收并校验北邮 CAS ticket' } },
    '/v1/auth/cas/complete': { post: { summary: '使用已校验的一次性 CAS 结果创建 FStudy 账户' } },
    // '/v1/auth/cas/password/challenge': { post: { summary: '获取北邮验证码和短期挑战' } },
    // '/v1/auth/cas/password/refresh': { post: { summary: '更换北邮验证码并获得新的挑战' } },
    // '/v1/auth/cas/password/verify': { post: { summary: '提交一次性北邮密码和验证码完成注册' } },
    '/v1/admin/auth/login': { post: { summary: '管理员独立登录' } },
    '/v1/admin/auth/logout': { post: { summary: '管理员退出登录' } },
    '/v1/admin/auth/password': { put: { summary: '修改管理员密码并撤销会话' } },
    '/v1/admin/overview': { get: { summary: '读取运营数据总览' } },
    '/v1/admin/users': { get: { summary: '搜索用户' } },
    '/v1/admin/users/{id}/status': { patch: { summary: '封禁或恢复用户' } },
    '/v1/admin/reports/{id}': { patch: { summary: '解决或驳回举报' } },
    '/v1/admin/content': { get: { summary: '读取待管理内容' } },
    '/v1/admin/content/{type}/{id}': { patch: { summary: '隐藏、恢复或删除内容' } },
    '/v1/admin/reports': { get: { summary: '处理举报' } },
    '/v1/admin/tags': { get: { summary: '管理受控标签' }, post: { summary: '创建或编辑受控标签' } },
    '/v1/admin/audit': { get: { summary: '读取管理操作审计日志' } },
  },
};

export function createApp(dependencies: RuntimeDependencies) {
  const accountService = new AccountService(dependencies);
  const tagService = new TagService(dependencies.database);
  const scheduleService = new ScheduleService(dependencies.database);
  const assignmentService = new AssignmentService(dependencies.database);
  const planService = new PlanService(dependencies.database);
  const discoveryService = new DiscoveryService(dependencies.database);
  const friendService = new FriendService(dependencies.database);
  const availabilityService = new AvailabilityService(dependencies.database);
  const projectService = new ProjectService(dependencies.database);
  const forumService = new ForumService(dependencies.database);
  const adminService = new AdminService(dependencies);
  const notificationService = new NotificationService(dependencies.database);
  const authentication = requireAuthentication(accountService);
  const adminAuthentication = requireAdminAuthentication(adminService);

  const app = new Hono<{ Variables: AppVariables }>();
  const allowedOrigins = new Set(dependencies.allowedOrigins ?? []);
  app.use('*', secureHeaders({
    crossOriginResourcePolicy: 'same-site',
    referrerPolicy: 'no-referrer',
    strictTransportSecurity: 'max-age=31536000; includeSubDomains',
  }));
  app.use('*', async (context, next) => {
    context.header('X-Request-Id', crypto.randomUUID());
    context.header('Cache-Control', 'no-store');
    context.header('Pragma', 'no-cache');
    await next();
  });
  app.use('*', cors({
    origin: (origin) => allowedOrigins.has(origin) ? origin : '',
    allowHeaders: ['Content-Type', 'Authorization'],
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    maxAge: 600,
  }));
  app.use('/v1/*', bodyLimit({
    maxSize: 64 * 1024,
    onError: (context) => context.json({
      error: { code: 'request_too_large', message: '请求体过大' },
    }, 413),
  }));
  app.use('/v1/*', async (context, next) => {
    if (['POST', 'PUT', 'PATCH'].includes(context.req.method)) {
      const contentType = context.req.header('content-type')?.split(';')[0]?.trim().toLowerCase();
      if (contentType !== 'application/json') {
        return context.json({
          error: { code: 'unsupported_media_type', message: '请求必须使用 application/json' },
        }, 415);
      }
    }
    await next();
  });

  app.get('/health', (context) => context.json({ status: 'ok' }, 200));
  app.get('/openapi.json', (context) => context.json(OPENAPI_DOCUMENT, 200));

  const casLogin = new CasLoginService(dependencies, accountService, allowedOrigins);
  const inviteService = new InviteService(dependencies.database, dependencies.clock);

  app.post('/v1/auth/cas/start', async (context) => {
    return context.json(await casLogin.startBrowserLogin(context.req.header('origin')), 200);
  });

  app.get('/v1/auth/cas/callback', async (context) => {
    const location = await casLogin.handleBrowserCallback(context.req.query('ticket'), context.req.query('state'));
    return context.redirect(location, 303);
  });

  app.post('/v1/auth/cas/complete', zValidator('json', CasCompleteSchema), async (context) => {
    const { code, state, displayName, appPassword, departmentId } = context.req.valid('json');
    const created = await casLogin.completeBrowserLogin({
      code, state, origin: context.req.header('origin'), displayName, appPassword, departmentId,
    });
    return context.json(created, 201);
  });

  app.post('/v1/admin/auth/login', zValidator('json', AdminLoginSchema), async (context) => {
    const { username, password } = context.req.valid('json');
    return context.json(await adminService.login(username, password), 200);
  });
  app.post('/v1/reports', authentication, zValidator('json', ContentReportSchema), async (context) => {
    const report = await adminService.createReport(context.get('userId'), context.req.valid('json'));
    return context.json({ report }, 201);
  });
  app.use('/v1/admin/*', async (context, next) => {
    if (context.req.path === '/v1/admin/auth/login') return next();
    return adminAuthentication(context, next);
  });
  app.post('/v1/admin/auth/logout', async (context) => {
    await adminService.logout(context.get('adminToken'));
    return context.json({ ok: true }, 200);
  });
  app.put('/v1/admin/auth/password', zValidator('json', AdminPasswordSchema), async (context) => {
    const input = context.req.valid('json');
    await adminService.changePassword(context.get('adminUsername'), input.currentPassword, input.newPassword);
    return context.json({ ok: true }, 200);
  });
  app.get('/v1/admin/overview', async (context) => context.json(await adminService.overview(), 200));
  app.get('/v1/admin/users', async (context) => context.json({
    users: await adminService.listUsers(context.req.query('q') ?? ''),
  }, 200));
  app.patch('/v1/admin/users/:id/status', zValidator('json', AdminUserStatusSchema), async (context) => {
    await adminService.setUserStatus(context.get('adminUsername'), context.req.param('id'), context.req.valid('json').status);
    return context.json({ ok: true }, 200);
  });
  app.get('/v1/admin/content', async (context) => context.json({ content: await adminService.listContent() }, 200));
  app.patch('/v1/admin/content/:type/:id', zValidator('json', AdminContentActionSchema), async (context) => {
    await adminService.moderateContent(
      context.get('adminUsername'), context.req.param('type'), context.req.param('id'), context.req.valid('json').action,
    );
    return context.json({ ok: true }, 200);
  });
  app.get('/v1/admin/reports', async (context) => context.json({ reports: await adminService.listReports() }, 200));
  app.patch('/v1/admin/reports/:id', zValidator('json', AdminReportStatusSchema), async (context) => {
    await adminService.updateReport(context.get('adminUsername'), context.req.param('id'), context.req.valid('json').status);
    return context.json({ ok: true }, 200);
  });
  app.get('/v1/admin/tags', async (context) => context.json({ tags: await adminService.listTags() }, 200));
  app.post('/v1/admin/tags', zValidator('json', AdminTagSchema), async (context) => {
    return context.json({ tag: await adminService.saveTag(context.get('adminUsername'), context.req.valid('json')) }, 200);
  });
  app.get('/v1/admin/audit', async (context) => context.json({ entries: await adminService.listAudit() }, 200));
  app.post('/v1/admin/invites', async (context) => {
    return context.json(await adminService.issueInvite(context.get('adminUsername')), 201);
  });

  app.post('/v1/auth/register', zValidator('json', RegisterSchema), async (context) => {
    if (!dependencies.inviteRegistrationEnabled) {
      throw new DomainError('registration_closed', '当前未开放注册', 403);
    }
    const result = await accountService.register(context.req.valid('json'));
    return context.json(result, 201);
  });

  // [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
  // app.post('/v1/auth/cas/password/challenge', zValidator('json', CasPasswordChallengeSchema), async (context) => {
    // const { studentId } = context.req.valid('json');
    // return context.json(await casLogin.issuePasswordChallenge(context.req.header('origin'), studentId), 200);
  // });

  // app.post('/v1/auth/cas/password/verify', zValidator('json', CasPasswordVerificationSchema), async (context) => {
    // const outcome = await casLogin.verifyPasswordChallenge(context.req.valid('json'));
    // if (outcome.kind === 'retry') {
      // return context.json({ error: { code: outcome.code, message: outcome.message }, retryAllowed: true }, 401);
    // }
    // return context.json(outcome.session, 201);
  // });

  // app.post('/v1/auth/cas/password/refresh', zValidator('json', CasPasswordRefreshSchema), async (context) => {
    // const { challengeId, studentId } = context.req.valid('json');
    // return context.json(await casLogin.refreshPasswordChallenge(challengeId, studentId), 200);
  // });

  app.post('/v1/auth/login', zValidator('json', LoginSchema), async (context) => {
    const result = await accountService.login(context.req.valid('json'));
    return context.json(result, 200);
  });

  app.use('/v1/me', authentication);
  app.use('/v1/me/*', authentication);
  app.use('/v1/courses', authentication);
  app.use('/v1/courses/*', authentication);
  app.use('/v1/assignments', authentication);
  app.use('/v1/assignments/*', authentication);
  app.use('/v1/plans', authentication);
  app.use('/v1/plans/*', authentication);
  app.use('/v1/tags', authentication);
  app.use('/v1/discover', authentication);
  app.use('/v1/friends', authentication);
  app.use('/v1/friend-requests', authentication);
  app.use('/v1/friend-requests/*', authentication);
  app.use('/v1/availability', authentication);
  app.use('/v1/availability-invites', authentication);
  app.use('/v1/availability-invites/*', authentication);
  app.use('/v1/projects', authentication);
  app.use('/v1/projects/*', authentication);
  app.use('/v1/project-applications', authentication);
  app.use('/v1/project-applications/*', authentication);
  app.use('/v1/forum/*', authentication);

  app.post('/v1/auth/logout', authentication, async (context) => {
    await accountService.revokeSession(context.get('accessToken'));
    return context.json({ ok: true }, 200);
  });

  app.get('/v1/me', async (context) => {
    const userId = context.get('userId');
    return context.json({
      user: await accountService.getUser(userId),
      email: await accountService.getEmail(userId),
    }, 200);
  });

  app.get('/v1/me/invites', async (context) => {
    return context.json(await inviteService.listForUser(context.get('userId')), 200);
  });

  app.post('/v1/me/invites', async (context) => {
    return context.json(await inviteService.issueForUser(context.get('userId')), 201);
  });

  app.get('/v1/me/academic-settings', async (context) => {
    const result = await dependencies.database.execute<{ semester_start_date: string | null }>({
      sql: 'SELECT semester_start_date FROM user_academic_settings WHERE user_id = ?',
      params: [context.get('userId')],
    });
    return context.json({ semesterStartDate: result.rows[0]?.semester_start_date ?? null }, 200);
  });

  app.get('/v1/notifications', authentication, async (context) => {
    return context.json(await notificationService.list(context.get('userId')), 200);
  });
  app.post('/v1/notifications/read', authentication, zValidator('json', NotificationReadSchema), async (context) => {
    const { id } = context.req.valid('json');
    await notificationService.markRead(context.get('userId'), id);
    return context.json(await notificationService.list(context.get('userId')), 200);
  });

  app.put('/v1/me/academic-settings', zValidator('json', AcademicSettingsSchema), async (context) => {
    const { semesterStartDate } = context.req.valid('json');
    const date = semesterStartDate ? new Date(`${semesterStartDate}T00:00:00.000Z`) : null;
    if (date && date.getUTCDay() !== 1) {
      throw new DomainError('invalid_semester_start_date', '第一周起始日期必须是星期一');
    }
    await dependencies.database.execute({
      sql: `INSERT INTO user_academic_settings (user_id, semester_start_date, updated_at)
        VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET
        semester_start_date = excluded.semester_start_date, updated_at = excluded.updated_at`,
      params: [context.get('userId'), semesterStartDate, new Date().toISOString()],
    });
    return context.json({ semesterStartDate }, 200);
  });

  app.patch('/v1/me', zValidator('json', ProfileSchema), async (context) => {
    const user = await accountService.updateUser(context.get('userId'), context.req.valid('json'));
    return context.json({ user }, 200);
  });

  app.get('/v1/tags', async (context) => context.json({ tags: await tagService.list() }, 200));

  app.post('/v1/tags', zValidator('json', CreateTagSchema), async (context) => {
    const result = await tagService.create(context.req.valid('json'));
    return context.json({ tag: result.tag }, result.created ? 201 : 200);
  });

  app.get('/v1/me/tags', async (context) => {
    return context.json({ tags: await tagService.listUserTags(context.get('userId')) }, 200);
  });

  app.put('/v1/me/tags', zValidator('json', UserTagsSchema), async (context) => {
    await tagService.replaceUserTags(context.get('userId'), context.req.valid('json').tags);
    return context.json({ ok: true }, 200);
  });

  app.get('/v1/discover', async (context) => {
    return context.json({ users: await discoveryService.discover(context.get('userId')) }, 200);
  });

  app.get('/v1/friends', async (context) => {
    return context.json(await friendService.list(context.get('userId')), 200);
  });

  app.post('/v1/friend-requests', zValidator('json', FriendRequestSchema), async (context) => {
    const request = await friendService.send(
      context.get('userId'),
      context.req.valid('json').targetUserId,
    );
    return context.json({ request }, 201);
  });

  app.patch(
    '/v1/friend-requests/:id',
    zValidator('json', FriendRequestActionSchema),
    async (context) => {
      await friendService.respond(
        context.get('userId'),
        context.req.param('id'),
        context.req.valid('json').action,
      );
      return context.json({ ok: true }, 200);
    },
  );

  app.get('/v1/forum/posts', async (context) => {
    const category = context.req.query('category');
    if (category && !['general', 'course', 'campus', 'experience'].includes(category)) {
      throw new DomainError('invalid_forum_category', '讨论分类无效');
    }
    return context.json({ posts: await forumService.list(category) }, 200);
  });

  app.post('/v1/forum/posts', zValidator('json', ForumPostSchema), async (context) => {
    const post = await forumService.createPost(context.get('userId'), context.req.valid('json'));
    return context.json({ post }, 201);
  });

  app.get('/v1/forum/posts/:id', async (context) => {
    return context.json(await forumService.get(context.req.param('id')), 200);
  });

  app.post('/v1/forum/posts/:id/replies', zValidator('json', ForumReplySchema), async (context) => {
    const reply = await forumService.createReply(
      context.get('userId'), context.req.param('id'), context.req.valid('json').body,
    );
    return context.json({ reply }, 201);
  });

  app.get('/v1/projects', async (context) => {
    const status = context.req.query('status');
    const tagId = context.req.query('tagId');
    if (status && !['recruiting', 'in_progress', 'closed'].includes(status)) {
      throw new DomainError('invalid_project_status', '项目状态无效');
    }
    return context.json({
      projects: await projectService.list(context.get('userId'), status, tagId),
    }, 200);
  });

  app.post('/v1/projects', zValidator('json', ProjectSchema), async (context) => {
    const project = await projectService.create(context.get('userId'), context.req.valid('json'));
    return context.json({ project }, 201);
  });

  app.patch('/v1/projects/:id/status', zValidator('json', ProjectStatusSchema), async (context) => {
    await projectService.setStatus(
      context.get('userId'), context.req.param('id'), context.req.valid('json').status,
    );
    return context.json({ ok: true }, 200);
  });

  app.post(
    '/v1/projects/:id/applications',
    zValidator('json', ProjectApplicationSchema),
    async (context) => {
      const application = await projectService.apply(
        context.get('userId'), context.req.param('id'), context.req.valid('json').message,
      );
      return context.json({ application }, 201);
    },
  );

  app.get('/v1/project-applications', async (context) => {
    return context.json({
      applications: await projectService.listApplications(context.get('userId')),
    }, 200);
  });

  app.patch(
    '/v1/project-applications/:id',
    zValidator('json', ProjectApplicationActionSchema),
    async (context) => {
      await projectService.respond(
        context.get('userId'), context.req.param('id'), context.req.valid('json').action,
      );
      return context.json({ ok: true }, 200);
    },
  );

  app.get('/v1/availability', zValidator('query', AvailabilityQuerySchema), async (context) => {
    return context.json(
      await availabilityService.query(context.get('userId'), context.req.valid('query')),
      200,
    );
  });

  app.get('/v1/availability-invites', async (context) => {
    return context.json(
      { invites: await availabilityService.listInvites(context.get('userId')) },
      200,
    );
  });

  app.post(
    '/v1/availability-invites',
    zValidator('json', AvailabilityInviteSchema),
    async (context) => {
      const invite = await availabilityService.createInvite(
        context.get('userId'),
        context.req.valid('json'),
      );
      return context.json({ invite }, 201);
    },
  );

  app.patch(
    '/v1/availability-invites/:id',
    zValidator('json', AvailabilityInviteActionSchema),
    async (context) => {
      await availabilityService.respond(
        context.get('userId'),
        context.req.param('id'),
        context.req.valid('json').action,
      );
      return context.json({ ok: true }, 200);
    },
  );

  app.get('/v1/courses', async (context) => {
    return context.json({ courses: await scheduleService.listCourses(context.get('userId')) }, 200);
  });

  app.post('/v1/courses', zValidator('json', CourseSchema), async (context) => {
    const course = await scheduleService.createCourse(context.get('userId'), context.req.valid('json'));
    return context.json({ course }, 201);
  });

  app.get('/v1/assignments', async (context) => {
    return context.json({ assignments: await assignmentService.list(context.get('userId')) }, 200);
  });

  app.post('/v1/assignments', zValidator('json', AssignmentSchema), async (context) => {
    const assignment = await assignmentService.create(context.get('userId'), context.req.valid('json'));
    return context.json({ assignment }, 201);
  });

  app.patch(
    '/v1/assignments/:id/completion',
    zValidator('json', CompletionSchema),
    async (context) => {
      const updated = await assignmentService.setCompleted(
        context.get('userId'),
        context.req.param('id'),
        context.req.valid('json').completed,
      );
      if (!updated) throw new DomainError('assignment_not_found', '作业不存在', 404);
      return context.json({ ok: true }, 200);
    },
  );

  app.get('/v1/plans', async (context) => {
    return context.json({ plans: await planService.list(context.get('userId')) }, 200);
  });

  app.post('/v1/plans', zValidator('json', PlanSchema), async (context) => {
    const plan = await planService.create(context.get('userId'), context.req.valid('json'));
    return context.json({ plan }, 201);
  });

  app.patch('/v1/plans/:id/completion', zValidator('json', CompletionSchema), async (context) => {
    await planService.setCompleted(
      context.get('userId'),
      context.req.param('id'),
      context.req.valid('json').completed,
    );
    return context.json({ ok: true }, 200);
  });

  app.notFound((context) => context.json({ error: { code: 'not_found', message: '接口不存在' } }, 404));
  app.onError((error, context) => {
    if (error instanceof DomainError) {
      return context.json({ error: { code: error.code, message: error.message } }, error.status);
    }
    console.error('Unhandled API error', error instanceof Error ? error.message : 'unknown');
    return context.json({ error: { code: 'internal_error', message: '服务器内部错误' } }, 500);
  });

  return app;
}
