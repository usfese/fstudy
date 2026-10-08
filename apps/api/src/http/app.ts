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
import { requireAuthentication, type AppVariables } from './auth.js';
import {
  AssignmentSchema,
  AvailabilityInviteActionSchema,
  AvailabilityInviteSchema,
  AvailabilityQuerySchema,
  CompletionSchema,
  CourseSchema,
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
    '/v1/auth/register': { post: { summary: '验证学生身份并注册' } },
    '/v1/auth/login': { post: { summary: '使用学号和本系统密码登录' } },
    '/v1/auth/logout': { post: { summary: '撤销当前会话并退出登录' } },
    '/v1/me': { get: { summary: '读取个人资料' }, patch: { summary: '更新个人资料和隐私偏好' } },
    '/v1/tags': { get: { summary: '读取受控标签' } },
    '/v1/me/tags': { get: { summary: '读取当前用户标签' }, put: { summary: '替换当前用户标签' } },
    '/v1/courses': { get: { summary: '读取课表' }, post: { summary: '添加课程' } },
    '/v1/assignments': { get: { summary: '读取作业' }, post: { summary: '添加作业' } },
    '/v1/plans': { get: { summary: '读取自定义安排' }, post: { summary: '添加自定义安排' } },
    '/v1/discover': { get: { summary: '发现可推荐的同学' } },
    '/v1/friends': { get: { summary: '读取好友及请求' } },
    '/v1/friend-requests': { post: { summary: '发送好友请求' } },
    '/v1/availability': { get: { summary: '查询好友共同空闲时间' } },
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
  const authentication = requireAuthentication(accountService);

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
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'OPTIONS'],
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

  app.post('/v1/auth/register', zValidator('json', RegisterSchema), async (context) => {
    const result = await accountService.register(context.req.valid('json'));
    return context.json(result, 201);
  });

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
    return context.json({ user: await accountService.getUser(context.get('userId')) }, 200);
  });

  app.patch('/v1/me', zValidator('json', ProfileSchema), async (context) => {
    const user = await accountService.updateUser(context.get('userId'), context.req.valid('json'));
    return context.json({ user }, 200);
  });

  app.get('/v1/tags', async (context) => context.json({ tags: await tagService.list() }, 200));

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
