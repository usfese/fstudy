# apps/api/src/modules — 业务模块

每个子目录是一个业务域，包含一个 `*Service` 类。服务通过构造函数接收 `SqlDatabase`（或完整的 `RuntimeDependencies`），**不直接接触 HTTP 对象**。路由层（`http/app.ts`）负责校验、鉴权和状态码。

## 模块一览

| 目录 | 服务类 | 职责 | 主要表 |
| --- | --- | --- | --- |
| `identity/` | `AccountService`、`CasLoginService` | 注册、登录、会话、资料、登录节流；CAS 浏览器登录与验证码流程 | `users`、`student_identities`、`credentials`、`sessions`、`auth_throttles`、`cas_*` |
| `tags/` | `TagService` | 受控标签列表与用户选择 | `tags`、`user_tags` |
| `schedule/` | `ScheduleService` | 手动课程与周次时间表 | `courses`、`course_meetings` |
| `assignments/` | `AssignmentService` | 作业与完成状态 | `assignments` |
| `plans/` | `PlanService` | 自定义安排（非课程的时间块） | `plans` |
| `discovery/` | `DiscoveryService` | 推荐同学（按标签与院系排序） | `users`、`user_tags`、`friendships`、`friend_requests` |
| `friends/` | `FriendService` | 好友请求与好友列表 | `friend_requests`、`friendships` |
| `availability/` | `AvailabilityService` | 共同空闲计算与空闲邀请 | `courses`、`course_meetings`、`plans`、`availability_invites` |
| `projects/` | `ProjectService` | 组队项目、标签、申请与成员 | `projects`、`project_tags`、`project_applications`、`project_members` |
| `forum/` | `ForumService` | 讨论帖与回复 | `forum_posts`、`forum_replies` |
| `admin/` | `AdminService` | 管理员认证、运营统计、审核、标签、审计 | `admin_accounts`、`admin_sessions`、`admin_login_throttles`、`admin_audit_log`、`content_reports` |
| `notifications/` | `NotificationService` | 站内通知（尽力投递） | `notifications` |

作业与自定义安排的完成状态分别存于 `assignments.completed_at` 与 `plans.completed_at`（`null` 表示未完成）。

---

## identity — `AccountService` 与 `CasLoginService`

### `CasLoginService`（`cas-login-service.ts`）

由路由 `http/app.ts` 调用，封装全部北邮 CAS 逻辑：

| 方法 | 对应接口 |
| --- | --- |
| `startBrowserLogin(origin)` | `POST /v1/auth/cas/start` |
| `handleBrowserCallback(ticket, state)` | `GET /v1/auth/cas/callback`（返回重定向地址） |
| `completeBrowserLogin(...)` | `POST /v1/auth/cas/complete` |
| `issuePasswordChallenge` / `refreshPasswordChallenge` / `verifyPasswordChallenge` | `/v1/auth/cas/password/*`（验证码流程，预发实验） |

校验顺序、错误码与数据库语句保持与重构前一致（由 `app.test.ts` 中的 CAS 测试覆盖）。

### `AccountService`

依赖 `RuntimeDependencies`（需要 `studentVerifier`、`studentIdPepper`、`clock`）。

### 公开方法

| 方法 | 说明 |
| --- | --- |
| `register({studentId, schoolPassword, appPassword, displayName, departmentId})` | 检查节流 → 调用 `studentVerifier.verify` → 401 时记一次失败 → 成功后清除失败记录 → `completeVerifiedIdentityHash` |
| `completeVerifiedIdentityHash({studentIdHash, displayName?, appPassword?, departmentId, allowExistingSession?})` | CAS 路径使用的版本。身份已存在：`allowExistingSession` 时直接发新会话，否则 409；身份不存在且缺少资料：409 `cas_registration_required`；否则 `batch` 写入 `users` + `student_identities` + `credentials` + `sessions` |
| `createSessionForVerifiedIdentityHash(hash)` | 为已存在的活跃用户签发新会话 |
| `login({studentId, appPassword})` | 节流检查 → 查询凭据 → 无论账号是否存在都执行一次 PBKDF2（`DUMMY_PASSWORD_CREDENTIAL`，防时序枚举）→ 失败统一返回 401 `invalid_credentials` |
| `authenticate(token)` | 校验令牌哈希、未撤销、未过期、用户 `active`，返回 `userId` |
| `revokeSession(token)` | 写 `revoked_at` |
| `getUser(userId)` | 返回 `PublicUser` |
| `updateUser(userId, patch)` | 更新资料与隐私设置 |

### 关键常量

| 常量 | 值 |
| --- | --- |
| 会话有效期 | 30 天 |
| 身份验证有效期（`student_identities.expires_at`） | 365 天。过期后不能登录，已有会话失效（[ADR-018](../../../../decisions.md#adr-018北邮身份-365-天有效过期需重新验证)） |
| 失败窗口 / 阈值 / 锁定时长 | 15 分钟 / 5 次 / 15 分钟 |

### 身份过期与续期（ADR-018）

- `login`：密码正确后检查 `expires_at`，过期返回 403 `identity_reverification_required`，且不计入失败次数。
- `authenticate`：通过 `student_identities` 连接查询，过期身份的会话视为无效。
- `renewIdentityIfExpired(studentIdHash)`：仅当身份已过期时，更新 `verified_at` 与 `expires_at` 并签发新会话。由 CAS 浏览器完成和验证码验证流程调用。

### 注意

- 登录与注册的节流都以 `student_id_hash` 为键（`auth_throttles.throttle_key`），因此不会把学号明文写入节流表。
- `register` 在 `DomainError.status === 401` 时才记录失败；503 等临时错误不计入。这是有意设计（有测试覆盖）。

---

## tags — `TagService`

- `list()`：全部 `active = 1` 的标签。
- `listUserTags(userId)`：用户已选标签，含 `isCore`、`visible`、`usedForRecommendation`。
- `replaceUserTags(userId, selections)`：**全量替换**。规则：最多 18 个；不能重复；所有 `tagId` 必须存在且 `active`；通过 `batch` 先删后插。

标签分三类：`interest`（兴趣）、`field`（方向）、`goal`（目标）。种子数据见 `migrations/0001_initial.sql`。

---

## schedule — `ScheduleService`

- `createCourse(userId, input)`：必须至少一个 `meetings`（否则 400 `meeting_required`）。课程与各个时间段在一次 `batch` 中写入。返回 `{ id }`。
- `listCourses(userId)`：按课程聚合 `meetings`，返回 `Course[]`。

时间规则在 Zod 层校验（见 `http/schemas.ts`）：`endMinute > startMinute`、`endWeek >= startWeek`、`weekParity` 取 `all/odd/even`。

**不做自动抓取课表**（`AGENT.md` 明确禁止）。

---

## assignments — `AssignmentService`

- `create(userId, input)`：`courseId` 若提供，必须属于当前用户，否则 404 `course_not_found`。返回 `{ id }`。
- `list(userId)`：按 `due_at` 排序。
- `setCompleted(userId, id, completed)`：返回 `boolean`（是否命中）。路由层据此返回 404。

---

## plans — `PlanService`

- `create`：校验 `endsAt > startsAt`（400 `invalid_plan_time`）。
- `list`：按开始时间排序。
- `setCompleted`：`completed_at` 置为当前时间或 `null`，不存在或不属于当前用户时 404 `plan_not_found`。

共同空闲只统计课程和未完成的安排（`plans`），**作业不参与**。

---

## discovery — `DiscoveryService`

用于 `/v1/discover`。

- 候选：`discoverable = 1`、`status = 'active'`、身份未过期（ADR-018）、不是自己。最多 50 人。
- 排序：`common_tag_count DESC`、`same_department DESC`、`display_name`。
- 共同标签：仅计算双方 `used_for_recommendation = 1` 的标签。
- 返回的标签只包括对方 `visible = 1` 的标签，并标记 `common`。
- 关系状态：`friends` / `outgoing` / `incoming` / `none`。

被封禁的用户（`status = 'suspended'`）不会出现。

---

## friends — `FriendService`

- `send(userId, targetUserId)`：不能加自己；目标必须 `active`、`discoverable` 且身份未过期；已是好友 409；已有待处理请求时区分方向（`request_already_sent` / `incoming_request_exists`）。使用 `pair_key`（两个 id 排序后用 `:` 连接）唯一约束。
- `respond(userId, requestId, action)`：`accept` / `reject` 只能由接收方操作；`cancel` 只能由发送方操作。`accept` 写入 `friendships`。
- `list(userId)`：返回 `{ friends, incoming, outgoing }`。

好友请求会触发 `friend_request` 通知（best-effort）。

---

## availability — `AvailabilityService`

这是隐私敏感模块。

### 好友关系与可见性

- `requireFriendship`：必须存在 `friendships` 记录（`pair_key` 相同），否则 403 `friendship_required`。
- 对方 `schedule_visibility = 'private'` 时拒绝，403 `schedule_private`。

### `query` — 计算共同空闲

输入：`friendId, date, weekNumber, dayStartMinute, dayEndMinute, timezoneOffsetMinutes`。

1. 将 `date` 解析为 UTC 零点，计算**用户时区**下的当天起止（`dayStartUtc = localMidnight - timezoneOffset`）。
2. 星期几：`getUTCDay() || 7`（周日为 7）。
3. 课程忙碌段：双方课程中 `weekday` 相同、周次覆盖 `weekNumber`、并满足 `week_parity`。
4. 安排忙碌段：双方未完成的 `plans`，与当天区间相交部分换算为分钟。
5. 合并区间，裁剪到 `[dayStartMinute, dayEndMinute]`，输出空闲段。

输出 `freeSlots`（双方课表计算的空闲段）和 `friendBlocks`（好友的忙碌段）。`friendBlocks` 按好友的 `schedule_visibility` 决定内容（[ADR-019](../../../../decisions.md#adr-019好友课表可见级别四级)）：

- `busy_only`：不返回 `friendBlocks`。
- `course_name`：返回忙碌段，包含课程名，安排标题为 `null`。
- `full`：返回忙碌段，包含课程名和安排标题。
- 安排备注在任何级别下都不返回。

### 邀请

- `createInvite`：`endsAt > startsAt`（400 `invalid_invite_time`），接收方必须是好友，写入 `pending` 并通知接收方。
- `respond`：仅 `pending` 可处理。`accept`/`reject` 只能由接收方；`cancel` 只能由发送方。

---

## projects — `ProjectService`

- `list(userId, status?, tagId?)`：只显示 `moderation_status = 'visible'` 的项目；可按状态和标签过滤。
- `create`：标签最多 8 个，且必须存在（`validateTags`）；项目与标签在一次写入中完成。
- `setStatus`：仅作者（`owner_id = userId`）可修改，否则 404 `project_not_found`（语义为“不存在或无权修改”）。
- `apply(userId, projectId, message)`：见 [http/README.md](../http/README.md#项目组队) 的业务规则。通知作者。
- `respond(userId, applicationId, action)`：
  - `accept`：由作者操作，**原子地**插入 `project_members`（`INSERT ... SELECT ... WHERE count < capacity`），再把申请标为 `accepted`。若插入未生效（满员或非招募中），抛出 409 `project_not_available`。
  - `reject`：由作者操作。
  - `withdraw`：由申请人操作。

---

## forum — `ForumService`

- `list(category?)`：只显示 `visible` 的帖子及回复数。
- `get(postId)`：帖子与所有 `visible` 回复（按时间升序）。
- `createPost`：每个用户每天最多 10 篇（429 `forum_post_rate_limited`）。
- `createReply`：每个用户每小时最多 30 条（429 `forum_reply_rate_limited`）；帖子必须 `visible`；通知作者。

---

## admin — `AdminService`

管理员与学生账户完全隔离（不同表、不同令牌、不同有效期）。

### 认证

- `bootstrap()`：仅在 `admin_accounts` 为空、且配置了用户名和密码时创建首个管理员；密码 ≥ 14 字符。
- `login(username, password)`：按用户名（小写）节流（5 次失败 / 15 分钟）；登录成功签发 8 天会话；不存在的用户也执行 PBKDF2（`DUMMY_CREDENTIAL`）。
- `authenticate(token)`：校验 `admin_sessions`。
- `changePassword(username, current, new)`：校验旧密码，写入新凭据，并撤销该管理员的所有会话。
- `logout(token)`。

### 运营与治理

| 方法 | 说明 |
| --- | --- |
| `overview()` | 用户、活跃用户、帖子、回复、项目、待处理举报、标签数、今日新增 |
| `listUsers(q)` | 按显示名模糊匹配，或按用户 id 精确匹配；最多 100 条，返回发帖数与项目数 |
| `setUserStatus(actor, userId, status)` | `suspended` 时同时把 `discoverable` 置为 0，并撤销该用户所有学生会话（`sessions.revoked_at`）；不存在返回 404；写审计 |
| `listContent()` | 帖子、回复、项目的汇总列表（含 `moderationStatus`） |
| `moderateContent(actor, type, id, action)` | `hide`/`restore` 改 `moderation_status`；`delete` 为 `DELETE`；写审计；不存在返回 404 |
| `createReport(reporterId, input)` | 举报；`targetType` ∈ `forum_post`/`forum_reply`/`project` |
| `listReports()` / `updateReport(actor, id, status)` | `resolved` / `dismissed` |
| `listTags()` / `saveTag(actor, input)` | 创建或编辑受控标签（`id` 可选，`category` ∈ interest/field/goal） |
| `listAudit()` | 最近的审计记录 |

审计动作命名示例：`content.hide`、`content.restore`、`content.delete`，实体类型为 `forum_post` / `forum_reply` / `project`。

---

## notifications — `NotificationService`

- `create({recipientId, actorId, kind, title, body, targetPath})`：自己给自己不通知；写入失败只记录日志。
- `list(userId)`：返回 `{ unreadCount, notifications[] }`，最近的在前。
- `markRead(userId, id?)`：不带 `id` 时全部标记为已读。

`kind` 取值：`friend_request`、`availability_invite`、`project_application`、`forum_reply`。

触发点：好友请求、空闲邀请、项目申请、论坛回复。前端通过轮询 `GET /v1/notifications` 获取（无推送）。

---

## 待确认事项

1. 过期身份的论坛帖与项目仍然公开可见（ADR-018 未覆盖内容下架）。
2. 生产环境目前没有可用的续期路径（ADR-018）。
3. `DiscoveryService` 没有过滤“已被对方拉黑”或“已屏蔽”的关系，因为目前没有屏蔽功能。
4. 管理员搜索无法按学号查询（学号只以 HMAC 存储），这是 [ADR-004](../../../../decisions.md#adr-004学号只以-hmac-形式保存不保存真实姓名与学校密码) 的有意取舍；若运营需要按学号查人，需要单独的受控流程。
