# apps/api/src/http — HTTP 路由与接口定义

本目录包含：

- `app.ts`：`createApp(dependencies)`，注册全部中间件与路由（约 550 行）。业务编排位于 `modules/`，CAS 登录与验证码流程由 `modules/identity/cas-login-service.ts` 处理。
- `auth.ts`：Bearer 令牌解析与两类鉴权中间件。
- `schemas.ts`：所有请求体/查询参数的 Zod Schema（请求边界校验）。

下文是**接口的权威定义**，与 `app.ts` 保持一致。字段名使用 JSON 的驼峰命名。

## 通用约定

### 全局中间件（按注册顺序）

1. `secureHeaders`：`Cross-Origin-Resource-Policy: same-site`、`Referrer-Policy: no-referrer`、HSTS 1 年。
2. 每个响应添加 `X-Request-Id`（UUID）、`Cache-Control: no-store`、`Pragma: no-cache`。
3. `cors`：仅当 `Origin` 在 `ALLOWED_ORIGINS` 中才回显；允许头 `Content-Type, Authorization`；方法 `GET/POST/PUT/PATCH/DELETE/OPTIONS`；`maxAge 600`。
4. `/v1/*`：`bodyLimit` 64 KB，超出返回 413 `request_too_large`。
5. `/v1/*`：`POST/PUT/PATCH` 的 `Content-Type` 必须是 `application/json`，否则 415 `unsupported_media_type`。

### 鉴权

- 学生接口：`Authorization: Bearer <token>`，令牌格式 `^[A-Za-z0-9_-]{40,128}$`。格式错误直接视为未登录。
- 管理接口（`/v1/admin/*`，但不含 `/v1/admin/auth/login`）：使用管理员令牌，和学生令牌互不通用。
- 未登录：401 `authentication_required`；令牌失效或用户被封禁：401 `invalid_session`。

### 错误格式

```json
{ "error": { "code": "snake_case_code", "message": "面向用户的中文说明" } }
```

`DomainError` 的 `status` 直接作为 HTTP 状态码。未捕获异常返回 500 `internal_error`。未匹配路由返回 404 `not_found`。

### 成功状态码

- 创建资源：`201`，并返回新资源（通常只含 `id` 或精简对象）。
- 更新操作：`200`，多数返回 `{ "ok": true }`。
- 列表：`200`，返回 `{ "<复数名>": [...] }`。

## 接口总览

> 列 “鉴权” 指是否需要学生 Bearer 令牌。

### 健康检查与文档

| 方法 | 路径 | 鉴权 | 响应 |
| --- | --- | --- | --- |
| GET | `/health` | 否 | `{ "status": "ok" }` |
| GET | `/openapi.json` | 否 | OpenAPI 3.1 文档（仅 summary） |

### 身份认证（学生）

注册与登录只使用用户名，不验证学生身份（ADR-021、ADR-023）。`/v1/auth/cas/*` 的浏览器登录路由保留但关闭，且不能创建新账户；验证码挑战路由已注释停用。

| 方法 | 路径 | 鉴权 | 请求体 / 参数 | 响应 |
| --- | --- | --- | --- | --- |
| POST | `/v1/auth/login` | 否 | `LoginSchema`：`username` (1–32，不区分大小写)、`appPassword` (1–128) | 200 `{ accessToken, expiresAt, user }` |
| POST | `/v1/auth/register` | 否 | `RegisterSchema`：`username`（3–20 位字母、数字或下划线）、`email`（有效邮箱，≤254，记录但不验证）、`appPassword`（10–128）、`displayName`（可选，1–30，默认同用户名）、`departmentId`（可空）、`inviteCode`（8–32，不区分大小写、忽略分隔符） | 201 `{ accessToken, expiresAt, user }`；邀请码无效或已用 403 `invalid_invite_code`；额度不适用于注册；注册关闭 403 `registration_closed`；用户名已存在 409 `username_already_registered`；邮箱已注册 409 `email_already_registered` |
| POST | `/v1/auth/logout` | 是 | — | 200 `{ ok: true }` |
| POST | `/v1/auth/cas/start` | 否（需 `Origin` 白名单） | — | 200 `{ authorizationUrl }`；`CAS_LOGIN_ENABLED` 为假时 503 `cas_login_disabled` |
| GET | `/v1/auth/cas/callback?ticket&state` | 否 | 查询参数 | 303 重定向到 `{return_origin}/login#cas_code=...&cas_state=...`；当前关闭 |
| POST | `/v1/auth/cas/complete` | 否 | `CasCompleteSchema`：`code`、`state`（32–128）、`displayName?`、`appPassword?`、`departmentId?` | 没有历史 `student_identities` 行时 403 `invite_registration_required`；仅历史身份可签发会话 |

注意：`/v1/auth/cas/complete` 仅供历史账户使用，不能创建或升级账户。该路由当前关闭。

### 个人资料与设置

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/me` | — | `{ user, email }`；`email` 为本人邮箱（未注册前的历史账户可能为 null） |
| PATCH | `/v1/me` | `ProfileSchema`：`displayName` (1–30)、`bio` (≤300)、`departmentId` (可空)、`discoverable` (bool)、`scheduleVisibility` ∈ `private`/`busy_only`/`course_name`/`full` | `{ user }` |

### 邀请码

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/me/invites` | — | `{ month, quota: 5, remainingThisMonth, invites: [{ id, createdAt, status: 'used' \| 'unused', usedAt }] }`（不返回邀请码本身） |
| POST | `/v1/me/invites` | `{}`（需 JSON Content-Type） | 201 `{ code, remainingThisMonth, month }`；码只显示一次。本月额度用完 429 `invite_quota_exceeded` |
| GET | `/v1/me/academic-settings` | — | `{ semesterStartDate }`（`YYYY-MM-DD` 或 null） |
| PUT | `/v1/me/academic-settings` | `{ semesterStartDate }`：ISO 日期或 null，**必须为星期一** | `{ semesterStartDate }`；非周一返回 400 `invalid_semester_start_date` |

`PublicUser`：`{ id, displayName, departmentId, bio, discoverable, scheduleVisibility, verifiedAt }`。

### 标签

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/tags` | 是 | `{ tags: Tag[] }`，仅 `active` 标签 |
| GET | `/v1/me/tags` | — | `{ tags: UserTag[] }` |
| PUT | `/v1/me/tags` | `UserTagsSchema`：`tags[]`（最多 18 个），每项 `{ tagId, isCore?, visible?, usedForRecommendation? }` | `{ ok: true }` |

> `/v1/tags` 需要登录（`app.use('/v1/tags', authentication)`），与 `AGENT.md` 的约定一致。

### 课表与作业

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/courses` | — | `{ courses: Course[] }` |
| POST | `/v1/courses` | `CourseSchema`：`name` (1–80)、`teacher?` (≤50)、`color` (`#RRGGBB`，默认 `#4F46E5`)、`meetings[]` (1–10 项) | 201 `{ course: { id } }` |
| GET | `/v1/assignments` | — | `{ assignments: Assignment[] }` |
| POST | `/v1/assignments` | `AssignmentSchema`：`courseId?` (uuid)、`title` (1–100)、`notes` (≤2000)、`dueAt?` (ISO 带时区) | 201 `{ assignment: { id } }` |
| PATCH | `/v1/assignments/:id/completion` | `{ completed: boolean }` | `{ ok: true }`；不存在 404 `assignment_not_found` |

`CourseSchema.meetings[]` 单项：

| 字段 | 约束 |
| --- | --- |
| `weekday` | 1–7（周一为 1） |
| `startMinute` / `endMinute` | 0–1439 / 1–1440，且 `end > start` |
| `startWeek` / `endWeek` | 1–30，且 `endWeek >= startWeek` |
| `weekParity` | `all` / `odd` / `even`，默认 `all` |
| `campus` / `building` / `room` | 可空，长度上限 50 / 80 / 50 |

### 自定义安排（Plans）

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/plans` | — | `{ plans: Plan[] }` |
| POST | `/v1/plans` | `PlanSchema`：`title` (1–100)、`notes` (≤2000)、`startsAt`、`endsAt`（ISO 带时区，结束晚于开始）、`reminderMinutes?` (0–10080) | 201 `{ plan: { id } }` |
| PATCH | `/v1/plans/:id/completion` | `{ completed: boolean }` | `{ ok: true }`；不存在或不属于当前用户时 404 `plan_not_found` |

### 发现与好友

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/discover` | — | `{ users: DiscoverUser[] }`（最多 50 人） |
| GET | `/v1/friends` | — | `{ friends, incoming, outgoing }` |
| POST | `/v1/friend-requests` | `{ targetUserId: uuid }` | 201 `{ request }` |
| PATCH | `/v1/friend-requests/:id` | `{ action: 'accept' \| 'reject' \| 'cancel' }` | `{ ok: true }` |

`DiscoverUser`：`{ id, displayName, departmentId, bio, sameDepartment, commonTagCount, relationship: none|outgoing|incoming|friends, tags: [{ id, category, name, isCore, common }] }`。

### 共同空闲

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/availability` | 查询：`friendId` (uuid)、`date` (YYYY-MM-DD)、`weekNumber` (1–30)、`dayStartMinute` (默认 480)、`dayEndMinute` (默认 1320)、`timezoneOffsetMinutes` (默认 480) | `{ date, weekNumber, freeSlots: [{ startMinute, endMinute }], friendBlocks: [{ startMinute, endMinute, kind: 'course' \| 'plan', title: string \| null }] }`；`friendBlocks` 按好友可见级别返回（ADR-019） |
| GET | `/v1/availability-invites` | — | `{ invites }` |
| POST | `/v1/availability-invites` | `{ friendId, startsAt, endsAt, title (1–100) }` | 201 `{ invite }` |
| PATCH | `/v1/availability-invites/:id` | `{ action: 'accept' \| 'reject' \| 'cancel' }` | `{ ok: true }` |

错误：非好友 403 `friendship_required`；对方课表为 `private` 时 403 `schedule_private`。

### 项目（组队）

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/projects?status=&tagId=` | `status` ∈ `recruiting`/`in_progress`/`closed`，否则 400 `invalid_project_status` | `{ projects }`（仅 `moderation_status=visible`） |
| POST | `/v1/projects` | `ProjectSchema`：`title` (1–100)、`description` (1–3000)、`capacity` (1–50)、`tagIds` (≤8) | 201 `{ project }` |
| PATCH | `/v1/projects/:id/status` | `{ status }` | `{ ok: true }`（仅作者） |
| POST | `/v1/projects/:id/applications` | `{ message: 1–500 }` | 201 `{ application: { id } }` |
| GET | `/v1/project-applications` | — | `{ applications }` |
| PATCH | `/v1/project-applications/:id` | `{ action: 'accept' \| 'reject' \| 'withdraw' }` | `{ ok: true }` |

业务规则：不能申请自己的项目；项目非 `recruiting` 不能申请（409 `project_not_recruiting`）；满员（409 `project_full`）；每小时最多申请 10 次（429）；重复申请 409 `application_already_exists`；接受时仍须校验名额。

### 论坛

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| GET | `/v1/forum/posts?category=` | `category` ∈ `general`/`course`/`campus`/`experience` | `{ posts }` |
| POST | `/v1/forum/posts` | `ForumPostSchema`：`category`、`title` (1–100)、`body` (1–5000) | 201 `{ post }` |
| GET | `/v1/forum/posts/:id` | — | `{ post, replies[] }`（仅 visible） |
| POST | `/v1/forum/posts/:id/replies` | `{ body: 1–2000 }` | 201 `{ reply: { id } }` |

### 举报与通知

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| POST | `/v1/reports` | `ContentReportSchema`：`targetType` ∈ `forum_post`/`forum_reply`/`project`，`targetId`，`reason` (5–500) | 201 `{ report }` |
| GET | `/v1/notifications` | — | `{ unreadCount, notifications[] }` |
| POST | `/v1/notifications/read` | `{ id? }`，省略 `id` 表示全部已读 | 同上 |

## 管理接口（`/v1/admin/*`）

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| POST | `/v1/admin/auth/login` | `{ username (3–64), password (1–128) }`（无需管理员令牌） | `{ accessToken, expiresAt, username }`（有效期 8 天） |
| POST | `/v1/admin/auth/logout` | — | `{ ok: true }` |
| PUT | `/v1/admin/auth/password` | `{ currentPassword, newPassword (≥14) }` | `{ ok: true }`，并撤销会话 |
| GET | `/v1/admin/overview` | — | `{ users, activeUsers, posts, replies, projects, openReports, tags, todayUsers, todayPosts, todayProjects }` |
| GET | `/v1/admin/users?q=` | — | `{ users }` |
| PATCH | `/v1/admin/users/:id/status` | `{ status: 'active' \| 'suspended' }` | `{ ok: true }`，封禁时撤销学生会话 |
| GET | `/v1/admin/content` | — | `{ content }`（论坛帖、回复、项目） |
| PATCH | `/v1/admin/content/:type/:id` | `{ action: 'hide' \| 'restore' \| 'delete' }`，`type` ∈ `forum_post`/`forum_reply`/`project` | `{ ok: true }`；`delete` 为物理删除 |
| GET | `/v1/admin/reports` | — | `{ reports }` |
| PATCH | `/v1/admin/reports/:id` | `{ status: 'resolved' \| 'dismissed' }` | `{ ok: true }` |
| GET | `/v1/admin/tags` | — | `{ tags }` |
| POST | `/v1/admin/tags` | `{ id?, category: interest/field/goal, name (1–40), active }` | `{ tag }` |
| GET | `/v1/admin/audit` | — | `{ entries }`（最近的管理操作） |
| POST | `/v1/admin/invites` | `{}` | 201 `{ code }`；运营码，不占用个人额度，写入审计日志 |

所有写操作都会写入 `admin_audit_log`（`actor`、`action`、`entity_type`、`entity_id`）。

## 错误码速查

| code | HTTP | 出处 |
| --- | --- | --- |
| `authentication_required` | 401 | 缺少令牌 |
| `invalid_session` | 401 | 令牌无效、过期、已撤销或用户被封禁 |
| `invalid_credentials` | 401 | 登录的用户名或密码错误（不区分是否存在账户） |
| `authentication_rate_limited` | 429 | 15 分钟内失败 5 次 |
| `registration_closed` | 403 | 注册已关闭（`INVITE_REGISTRATION_ENABLED` 未开启） |
| `invite_registration_required` | 403 | CAS 结果不能绕过邀请码创建新账户 |
| `invalid_invite_code` | 403 | 邀请码无效或已被使用 |
| `invite_quota_exceeded` | 429 | 本月邀请码额度已用完（每人每月 5 个） |
| `email_already_registered` | 409 | 邮箱已注册 |
| `registration_conflict` | 409 | 注册时用户名或邮箱发生并发冲突 |
| `username_already_registered` | 409 | 该用户名已被使用 |
| `student_not_registered` | 404 | CAS 登录时身份不存在 |
| `school_auth_*` / `school_identity_mismatch` | 401/503 | 学校验证已停用，这些错误码只在已注释的代码中出现，见 [adapters/README.md](../adapters/README.md) |
| `cas_*` / `invalid_cas_*` | 400–503 | 浏览器 CAS 与验证码流程 |
| `request_too_large` | 413 | 请求体超过 64 KB |
| `unsupported_media_type` | 415 | 非 JSON 请求 |
| `not_found` / `assignment_not_found` / `project_not_found` 等 | 404 | 资源不存在 |
| `internal_error` | 500 | 未分类异常 |

完整 code 列表以 `grep -rn "new DomainError" apps/api/src` 为准。

## OpenAPI 覆盖情况

`OPENAPI_DOCUMENT` 为手写对象，只包含 `summary`，没有请求/响应 Schema。路径层面已与路由一致，`pnpm knowledge:check` 会检查每个注册路由都在文档中。

## 待确认 / 已知问题

1. 管理员登录放行依赖 `context.req.path === '/v1/admin/auth/login'` 的字符串比较。新增同前缀的公开管理接口时，需要同步修改该判断。
