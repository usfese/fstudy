# 架构决策记录（ADR）

每条记录包含：决策、背景/理由、影响、依据。“依据”指向文档或代码位置，便于核对。状态为 `生效` 或 `已替代`。

## 索引

读取本表即可判断是否相关；需要细节时用 `grep -n "## ADR-0xx" docs/knowledge/decisions.md` 只读对应条目。

| ID | 决策摘要 | 状态 | 关键词 |
| --- | --- | --- | --- |
| ADR-001 | API 使用 Hono，同一业务代码跑 Node 与 Workers | 生效 | runtime, hono, entrypoint, createApp |
| ADR-002 | 数据库经 SqlDatabase 接口抽象 | 生效 | D1, node:sqlite, batch, adapter |
| ADR-003 | 学生与管理员两套独立不透明令牌会话 | 生效 | token, session, admin, sessionStorage |
| ADR-004 | 学号仅存 HMAC，不存姓名与学校密码 | 生效 | pepper, HMAC, student id, privacy |
| ADR-005 | 应用密码 PBKDF2-SHA256 100k 次 | 生效 | PBKDF2, password, Workers limit |
| ADR-006 | 学生身份采用 CAS-only，生产默认关闭 | 生效 | CAS, BUPT, auth, captcha, UCloud |
| ADR-007 | 预发允许临时加密保存 CAS 状态（仅 staging） | 生效 | AES-GCM, encrypted_state, staging |
| ADR-008 | 标签为受控词表 | 生效 | tags, controlled vocabulary, recommendation |
| ADR-009 | 发现与好友隐私优先，只返回空闲段 | 生效 | discover, friendship, availability, privacy |
| ADR-010 | 内容软隐藏 + 举报 + 审计 | 生效 | moderation, report, audit, delete |
| ADR-011 | 通知尽力投递，无系统推送 | 生效 | notification, best-effort, polling |
| ADR-012 | 并发安全靠 SQL 条件写入 | 生效 | concurrency, capacity, batch, project |
| ADR-013 | 速率限制落在数据库 | 生效 | rate limit, throttle, lockout |
| ADR-014 | Flutter Web 优先，Android/iOS 暂缓 | 生效 | Flutter, Web, Android, scope |
| ADR-015 | Flutter 仓库接口 + Dio + go_router | 生效 | repository, Dio, go_router, secure storage |
| ADR-016 | 管理后台为独立静态前端 | 生效 | admin, static, origin |
| ADR-017 | 迁移只做前向变更（本地按标志表或索引检测） | 生效 | migration, D1, forward-only, node.ts |
| ADR-018 | 北邮身份 365 天有效，过期需重新验证 | 生效 | identity, expiry, re-verification, CAS |
| ADR-019 | 好友课表可见级别（四级） | 生效 | schedule_visibility, friendBlocks, privacy |
| ADR-020 | 保留预留依赖（本地通知、riverpod、drift） | 生效 | Android, notification, dependency |

---

## ADR-001：API 使用 Hono + TypeScript，同一份业务代码同时运行于 Node.js 与 Cloudflare Workers

- **状态**：生效
- **决策**：HTTP 层统一使用 Hono；`createApp(dependencies)` 是唯一的应用工厂，`entrypoints/node.ts` 与 `entrypoints/worker.ts` 只负责组装依赖。
- **理由**：本地开发用 Node + `node:sqlite` 快速迭代，生产用 Workers + D1 低运维成本。两个运行时必须共享同一套业务逻辑，避免分叉。
- **影响**：运行时差异必须收敛在 `adapters/` 与入口文件中；禁止为某个运行时单独实现业务规则。
- **依据**：`AGENT.md`「Architecture Boundaries」「Repository Layout」；`apps/api/src/http/app.ts`。

## ADR-002：数据库通过 `SqlDatabase` 接口抽象

- **状态**：生效
- **决策**：业务模块只依赖 `SqlDatabase`（`execute` / `batch`），实现有 `D1SqlDatabase` 与 `NodeSqliteDatabase`。
- **理由**：`batch` 用于需要原子性的多语句写入（如注册时同时写 `users`、`student_identities`、`credentials`、`sessions`）。
- **影响**：SQL 以字符串形式写在服务中，跨方言差异需谨慎（例如 `node:sqlite` 的 `batch` 使用 `BEGIN IMMEDIATE`，D1 使用其原生 batch）。
- **依据**：`apps/api/src/core/types.ts`、`apps/api/src/adapters/*-database.ts`。

## ADR-003：学生与管理员使用两套互相独立的不透明令牌会话

- **状态**：生效
- **决策**：
  - 学生会话：32 字节随机令牌（base64url），数据库只保存 SHA-256 哈希，有效期 30 天，`sessions` 表。
  - 管理员会话：同样的哈希方式，有效期 8 天，`admin_sessions` 表；路由通过 `/v1/admin/*` 中间件强制鉴权。
  - 管理台令牌只存于当前标签页的 `sessionStorage`。
- **理由**：管理员权限与学生身份完全隔离，学生令牌不能访问管理接口。不存明文令牌，数据库泄露不直接等于会话泄露。
- **影响**：撤销时更新 `revoked_at`；封禁用户时会立即撤销其会话。
- **依据**：`apps/api/src/modules/identity/account-service.ts`、`apps/api/src/modules/admin/admin-service.ts`、`apps/api/src/http/auth.ts`、`README.md`「管理控制台」。

## ADR-004：学号只以 HMAC 形式保存，不保存真实姓名与学校密码

- **状态**：生效
- **决策**：学号经 `HMAC-SHA256(pepper, studentId)` 后存入 `student_identities.student_id_hash`；`STUDENT_ID_PEPPER` 为 Wrangler secret，生产启动前校验长度不少于 32。学校密码只在请求内存中使用，不写日志、不落库；真实姓名不落库。
- **理由**：防止学号被撞库还原，同时保证“一个学号只能注册一个账户”的唯一性。
- **影响**：学号丢失无法从数据库反查；pepper 变更会导致所有既有身份失效，必须视为不可更换的密钥。
- **依据**：`AGENT.md`「Security and Identity」；`apps/api/src/core/security.ts`；`apps/api/src/entrypoints/*.ts`。

## ADR-005：应用密码使用 PBKDF2-SHA256，迭代次数 100,000

- **状态**：生效
- **决策**：`createPasswordCredential` 使用 16 字节随机盐、100,000 次迭代、输出 256 位；验证时对不合法的迭代次数直接返回失败。
- **理由**：Cloudflare Workers 的 WebCrypto 目前拒绝超过 100,000 的 PBKDF2 迭代次数，因此选择此上限。
- **影响**：未来若提高迭代次数，需要兼容既有凭据（`password_iterations` 字段已存于每条记录，可逐步迁移）。
- **依据**：`apps/api/src/core/security.ts` 注释；`apps/api/test/security.test.ts`。

## ADR-006：学生身份认证采用 CAS-only 方案，生产默认关闭

- **状态**：生效（其中验证码部分仍在实验中）
- **决策**：
  1. 本地 `AUTH_MODE=dev` 使用 `DevelopmentStudentVerifier`（固定密码 `dev-password`）。
  2. 生产 `AUTH_MODE=disabled` 使用 `DisabledStudentVerifier`，所有注册返回 503。
  3. `AUTH_MODE=bupt-cas` 仅访问 `auth.bupt.edu.cn` 的 CAS 登录与 `serviceValidate`，不请求 UCloud token 或角色接口。
  4. 浏览器跳转式 CAS 因北邮返回“未认证授权的服务”而保持关闭（`CAS_LOGIN_ENABLED=false`）。
  5. 预发环境的“学校密码 + 人工验证码”流程仅作为实验，验证码必须由用户在界面中人工输入，禁止 OCR、绕过或自动重试。
- **理由**：用户未获得北邮正式授权；第三方库 `byrdocs/bupt-auth` 不是官方接口，且其 UCloud 流程被明确禁止使用。
- **影响**：
  - 不能宣称“密码无法被服务端看到”——直接提交密码时 Worker 会在内存中收到学校密码，再转发给 CAS。
  - 生产注册在完成安全评审与授权前保持关闭。
- **依据**：`AGENT.md`「Security and Identity」「Handoff」；`README.md`「BUPT CAS-only 验证（实验性）」；`apps/api/src/adapters/student-verifier.ts`。

## ADR-007：预发环境允许临时加密保存 CAS 会话状态（仅 staging）

- **状态**：生效（仅预发，生产禁止）
- **决策**：验证码挑战的 CAS cookie 与 execution 参数以 AES-GCM 加密后存入 `cas_password_challenges.encrypted_state`，密钥为 `CAS_STATE_ENCRYPTION_KEY`（Wrangler secret，至少 32 字符，内部取 SHA-256 作为密钥）。挑战 5 分钟过期、一次性使用、最多尝试 3 次，完成或失败后立即清空密文。
- **理由**：用户明确批准的预发实验。
- **依据**：`AGENT.md`「Security and Identity」例外条款；`apps/api/src/core/security.ts`（`encryptCasState` / `decryptCasState`）；`apps/api/src/http/app.ts`（`/v1/auth/cas/password/*`）；`migrations/0012`、`0013`。

## ADR-008：数据库中的标签为受控词表，由种子数据和管理员维护

- **状态**：生效
- **决策**：`tags` 表由 `0001_initial.sql` 写入初始种子（兴趣、方向、目标三类）；用户标签只能从受控词表中选择（`PUT /v1/me/tags` 最多 18 个），管理员通过 `/v1/admin/tags` 创建或停用。项目标签最多 8 个。
- **理由**：推荐算法依赖稳定的标签，自由文本会导致匹配失效和内容质量问题。
- **影响**：`active=0` 的标签不会出现在推荐与列表中。
- **依据**：`apps/api/migrations/0001_initial.sql`；`modules/tags/tag-service.ts`；`modules/admin/admin-service.ts`。

## ADR-009：发现与好友默认隐私优先

- **状态**：生效
- **决策**：
  - 用户默认 `discoverable = 0`，只有主动开启后才会出现在 `/v1/discover`。
  - 只有互为好友后才能查询对方的共同空闲时间，且 `schedule_visibility = private` 时拒绝查询。
  - 共同空闲接口只返回空闲区间（`freeSlots`），不返回课程名称或具体安排。
  - 管理员封禁用户后，该用户不再出现在发现列表中。
- **理由**：`AGENT.md` 要求“隐私优先”，且明确不做私信；共同空闲是邀请的前置条件。
- **影响**：`schedule_visibility` 的分级语义已由 [ADR-019](#adr-019好友课表可见级别四级) 定义并实现。
- **依据**：`apps/api/src/modules/discovery/discovery-service.ts`、`availability/availability-service.ts`、`AGENT.md`「first usable release」。

## ADR-010：内容治理采用“软隐藏 + 举报 + 审计”，不做物理删除优先

- **状态**：生效
- **决策**：论坛帖、回复和项目均有 `moderation_status`（`visible` / `hidden`）；管理员可 `hide` / `restore` 做软隐藏，`delete` 则是真正的 `DELETE`（见 `admin-service.ts` 的 `moderateContent`）。所有管理操作写入 `admin_audit_log`。
- **理由**：日常处理使用可逆的隐藏，只有明确需要时才物理删除；审计日志保留操作证据。
- **影响**：`delete` 依赖外键级联删除相关回复与项目成员记录，操作不可逆。
- **依据**：`apps/api/migrations/0008_admin.sql`；`modules/admin/admin-service.ts`。

## ADR-011：通知为尽力投递，不影响主业务

- **状态**：生效
- **决策**：`NotificationService.create` 捕获存储异常并只记录日志，好友请求、项目申请、论坛回复等动作不会因通知失败而报错。站内通知为轮询式（前端 `GET /v1/notifications`），**不做系统推送**。
- **理由**：AGENT.md 明确当前阶段暂缓 Android 本地通知与系统推送。
- **依据**：`apps/api/src/modules/notifications/notification-service.ts`；`AGENT.md`「Current iteration constraint」。

## ADR-012：并发安全通过 SQL 条件写入保证，而不是应用层加锁

- **状态**：生效
- **决策**：项目成员上限在 `INSERT ... SELECT ... WHERE (SELECT COUNT(*)) < capacity` 中判断；申请处理的 `UPDATE` 带 `status = 'pending'` 条件；`batch` 在同一事务中执行。
- **理由**：Workers 无长连接内存状态，无法依赖进程内锁。
- **依据**：`apps/api/src/modules/projects/project-service.ts`；测试 `does not overfill a project when applications are accepted concurrently`。

## ADR-013：速率限制落在数据库中

- **状态**：生效
- **决策**：
  - 学生登录/注册失败：同一学号哈希在 15 分钟窗口内失败 5 次即锁定 15 分钟（`auth_throttles`）。
  - 管理员登录：按用户名锁定（`admin_login_throttles`）。
  - 项目申请：每用户每小时最多 10 次。
  - CAS 验证码签发：同一学号 15 分钟内最多 5 次。
  - 北邮服务暂时不可用（503）不计入密码失败次数。
- **理由**：无状态运行时只能使用持久化计数，且需跨 Worker 实例一致。
- **依据**：`modules/identity/account-service.ts`、`modules/admin/admin-service.ts`、`modules/projects/project-service.ts`、`http/app.ts`。

## ADR-014：Flutter 客户端采用 Web 优先，Android/iOS 按需恢复

- **状态**：生效
- **决策**：当前迭代以 Flutter Web/PWA 为主要验证目标，`flutter analyze`、`flutter test` 与 Web 构建为门槛；不构建 APK/AAB；iOS 工程保留但不构建。
- **理由**：快速迭代；Android 通知与真机测试成本高，用户明确推迟。
- **影响**：共享代码需保持可移植；`flutter_local_notifications` 等依赖已声明但暂未在 `lib/` 中使用。
- **依据**：`AGENT.md`「Current iteration constraint」。

## ADR-015：Flutter 客户端采用仓库接口 + Dio 实现 + go_router 路由

- **状态**：生效
- **决策**：每个功能目录有 `*_repository.dart`，定义 `abstract interface class`，并提供 `Dio*Repository` 实现；UI 只依赖接口。`app.dart` 是唯一的组装点，通过 `*RepositoryFactory` 注入。令牌存于 `flutter_secure_storage`（键 `fstudy_access_token`）。
- **理由**：测试时可注入 fake 仓库，避免真实网络请求。
- **依据**：`AGENT.md`「Flutter」；`apps/mobile/lib/app.dart`、`features/auth/auth_repository.dart`。

## ADR-016：管理后台为独立的静态前端

- **状态**：生效
- **决策**：`apps/admin` 是不带构建步骤的纯 HTML/JS，通过 `window.FSTUDY_API_URL` 指定 API 地址，与学生端 Flutter 应用完全分离。
- **理由**：降低运维复杂度，并将管理面与学生面隔离到不同来源（origin）。
- **依据**：`README.md`「管理控制台」；`apps/admin/`。

## ADR-017：数据库迁移只允许前向变更

- **状态**：生效（本地入口使用手写检测，见下）
- **决策**：`apps/api/migrations/` 中的 SQL 按编号递增；已部署的迁移禁止修改；生产使用 `wrangler d1 migrations apply`。
- **偏差**：本地 `entrypoints/node.ts` 没有使用迁移记录表，而是对每个迁移检查标志表或索引是否存在后再执行，需要与远程保持同步的手工维护。`0013` 已改为检测其索引名。
- **依据**：`AGENT.md`「Data and Destructive Operations」「Architecture Boundaries」；`apps/api/src/entrypoints/node.ts`。

## ADR-018：北邮身份 365 天有效，过期需重新验证

- **状态**：生效
- **决策**：`student_identities.expires_at` = 验证时间 + 365 天，并强制执行：
  - 登录：密码正确后若身份已过期，返回 403 `identity_reverification_required`。该分支不计入失败次数。
  - 会话：`authenticate` 与会话签发都检查身份有效期，过期身份的已有会话立即失效。
  - 社交：发现列表、好友申请的目标、共同空闲的对象都排除过期身份。
  - 续期：一次新的学校验证（浏览器 CAS 完成，或验证码流程）若命中已过期身份，则更新 `verified_at` 与 `expires_at`，并签发新会话。资料与本系统密码不变。
- **理由**：学籍状态会变化（毕业、休学），身份需要定期确认。
- **影响**：
  - 过期用户的论坛帖与项目内容仍然公开可见，本决定不处理内容下架。
  - 续期依赖学校验证路径。当前浏览器 CAS 已关闭，验证码流程仅在预发实验，所以**生产环境目前无法续期**。在开放注册前必须解决续期路径。
- **依据**：`apps/api/src/modules/identity/account-service.ts`（`login`、`authenticate`、`renewIdentityIfExpired`）、`cas-login-service.ts`、`test/app.test.ts`。

## ADR-019：好友课表可见级别（四级）

- **状态**：生效
- **决策**：`users.schedule_visibility` 从好友视角决定可见范围：

  | 级别 | 共同空闲段 `freeSlots` | `friendBlocks`（好友忙碌段） | 课程名 | 安排标题 | 备注 |
  | --- | --- | --- | --- | --- | --- |
  | `private` | 不可查询（403） | — | — | — | — |
  | `busy_only`（默认） | 返回 | 不返回 | 否 | 否 | 否 |
  | `course_name` | 返回 | 返回，安排为无标题的忙碌段 | 是 | 否 | 否 |
  | `full` | 返回 | 返回 | 是 | 是 | 否 |

- **备注**：安排备注（`plans.notes`）在任何级别下都不返回。`freeSlots` 始终由双方课表计算。
- **理由**：默认最保守；每升高一级，只增加一类信息。
- **影响**：共同空闲响应新增 `friendBlocks` 字段，只包含好友的忙碌段，并已裁剪到查询窗口内。
- **依据**：`apps/api/src/modules/availability/availability-service.ts`（`query`）；`test/app.test.ts` 中的可见级别测试。

## ADR-020：保留预留依赖（本地通知、riverpod、drift）

- **状态**：生效（与 ADR-014 相关）
- **决策**：`flutter_local_notifications` 保留，为未来的 Android 版本和本地提醒预留。`flutter_riverpod` 与 `drift` 也保留，视为预留依赖，直到它们被实际使用或用户明确移除。`sqlite3` 钉死版本的原因不变。
- **理由**：产品计划推出 Android 版本，本地通知是其中的一部分。
- **影响**：这三个依赖已声明但 `lib/` 中暂未引用，属于有意保留。它们不影响 Web 构建，但会增加依赖解析的时间。
- **依据**：用户决定（2026-10-14）；`apps/mobile/pubspec.yaml`。

