# apps/api/migrations — 数据库迁移与表结构

SQL 迁移为前向迁移，编号递增。**已部署（远程 D1）的迁移不得修改**，需要变更时新增文件。

- 远程（预发/生产）：`pnpm db:migrate:remote`（即 `wrangler d1 migrations apply fstudy --remote`）。
- 本地 Node：启动时由 `entrypoints/node.ts` 按“标志表或索引是否存在”自动执行（见下方“迁移历史”的说明）。
- 预发与生产远程历史均已到 `0015_usernames.sql`（2026-10-22）。预发 D1 为 `fstudy-staging`，生产 D1 为 `fstudy`（`a0fb31d4-6d34-42db-9895-daf724d8bd25`）。**不要重置远程数据库**。

## 迁移历史

| 编号 | 文件 | 内容 | 本地入口检测 |
| --- | --- | --- | --- |
| 0001 | `0001_initial.sql` | 用户、身份、凭据、会话、标签、课程、课程时间、作业；**写入标签种子数据** | `users` |
| 0002 | `0002_plans.sql` | 自定义安排 `plans` | `plans` |
| 0003 | `0003_friends.sql` | 好友请求、好友关系 | `friend_requests` |
| 0004 | `0004_availability.sql` | 共同空闲邀请 | `availability_invites` |
| 0005 | `0005_auth_throttles.sql` | 登录节流 | `auth_throttles` |
| 0006 | `0006_projects.sql` | 项目、项目标签、申请、成员 | `projects` |
| 0007 | `0007_forum.sql` | 论坛帖子与回复 | `forum_posts` |
| 0008 | `0008_admin.sql` | 管理员、管理会话、审计、举报；给 `forum_posts`、`forum_replies`、`projects` 增加 `moderation_status` | `admin_sessions` |
| 0009 | `0009_academic_settings.sql` | 学期第一周起始日期 | `user_academic_settings` |
| 0010 | `0010_notifications.sql` | 站内通知 | `notifications` |
| 0011 | `0011_cas_browser_login.sql` | CAS 跳转登录的 state 与一次性 code（入口已关闭） | `cas_login_states` |
| 0012 | `0012_cas_password_challenges.sql` | 验证码挑战表（含 `attempt_count`；流程已停用，表保留） | `cas_password_challenges` |
| 0013 | `0013_cas_challenge_attempts.sql` | 仅创建 `(student_id_hash, attempt_count, expires_at)` 索引 | 检测索引 `cas_password_challenges_attempts_idx` 缺失 |
| 0014 | `0014_invites_and_email.sql` | 邀请码 `invite_codes`、用户邮箱 `user_emails`（ADR-021）。预发与生产均已执行 | `invite_codes` |
| 0015 | `0015_usernames.sql` | 给 `users` 增加 `username` 并回填旧账户，建立唯一索引（ADR-023）。预发与生产均已执行（2026-10-22） | `users.username` |

### 迁移历史的注意事项

- **远程一致性已核对（2026-10-14）**：`d1_migrations` 最新记录为 `0013_cas_challenge_attempts.sql`（其前为 `0012`、`0011`）。远程 `cas_password_challenges` 的 `CREATE TABLE` 含 `attempt_count`，索引包含 `cas_password_challenges_attempts_idx`，与仓库中的 `0012`、`0013` 完全一致。之前担心的“远程 0013 为 ALTER TABLE 而仓库已改写”的问题不存在。
  - 核对方法（只读）：`wrangler d1 execute fstudy-staging --remote --command "SELECT name FROM d1_migrations ORDER BY id DESC LIMIT 3; SELECT sql FROM sqlite_master WHERE tbl_name = 'cas_password_challenges';"`。新增远程迁移前应重复此步骤。
- 本地检测已修正为按索引名判断，因此本地库也会创建该索引，与远程的索引集合一致（前提是远程确实执行过 `0013`）。
- 建议：统一为迁移记录表（例如 `d1_migrations` 或 `schema_migrations`），用同一套逻辑驱动本地与远程。在此之前，新增迁移时必须同时在 `node.ts` 中加入检测分支，并在 `test/app.test.ts` 的迁移列表中补充。

## 表结构概览

### 身份与会话

| 表 | 主键 | 关键字段 | 说明 |
| --- | --- | --- | --- |
| `users` | `id` | `username`(UNIQUE)、`display_name`、`department_id`、`bio`、`discoverable`(0/1)、`schedule_visibility`、`status`(active/suspended/deleted) | 学生用户；用户名是登录标识（ADR-023） |
| `student_identities` | `user_id` | `student_id_hash` (UNIQUE)、`verified_department_id`、`verified_at`、`expires_at` | **历史/预留**：新账户不再写入；学号列保留供未来扩展 |
| `credentials` | `user_id` | `password_hash`、`password_salt`、`password_iterations` | PBKDF2 凭据 |
| `sessions` | `id` | `token_hash` (UNIQUE)、`expires_at`、`revoked_at` | 学生会话 |
| `auth_throttles` | `throttle_key` | `failure_count`、`window_started_at`、`blocked_until` | 登录标识哈希维度的失败节流 |

### 课表与学习

| 表 | 主键 | 关键字段 |
| --- | --- | --- |
| `courses` | `id` | `user_id`、`name`、`teacher`、`color` |
| `course_meetings` | `id` | `course_id`、`weekday`(1–7)、`start_minute`、`end_minute`、`start_week`、`end_week`、`week_parity`(all/odd/even)、`campus`、`building`、`room` |
| `assignments` | `id` | `user_id`、`course_id`(可空, ON DELETE SET NULL)、`title`、`notes`、`due_at`、`completed_at` |
| `plans` | `id` | `user_id`、`title`、`notes`、`starts_at`、`ends_at`、`reminder_minutes`、`completed_at` |
| `user_academic_settings` | `user_id` | `semester_start_date` |

### 标签

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `tags` | `id` | 受控词表；`category` ∈ interest/field/goal；`UNIQUE(category, name)`；`active` |
| `user_tags` | `(user_id, tag_id)` | `is_core`、`visible`、`used_for_recommendation` |

### 社交

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `friend_requests` | `id` | `pair_key` (UNIQUE)、`sender_id`、`receiver_id`、`status` ∈ pending/accepted/rejected/canceled |
| `friendships` | `pair_key` | `user_a_id`、`user_b_id`（pair_key 为两个 id 排序后拼接） |
| `availability_invites` | `id` | `sender_id`、`receiver_id`、`starts_at`、`ends_at`、`title`、`status` ∈ pending/accepted/rejected/canceled |

### 项目与论坛

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `projects` | `id` | `owner_id`、`title`、`description`、`status` ∈ recruiting/in_progress/closed、`capacity`(1–50)、`moderation_status` |
| `project_tags` | `(project_id, tag_id)` | 项目标签 |
| `project_applications` | `id` | `UNIQUE(project_id, applicant_id)`、`message`、`status` ∈ pending/accepted/rejected/withdrawn |
| `project_members` | `(project_id, user_id)` | 已接纳成员 |
| `forum_posts` | `id` | `author_id`、`category` ∈ general/course/campus/experience、`title`、`body`、`moderation_status` |
| `forum_replies` | `id` | `post_id`、`author_id`、`body`、`moderation_status` |

### 管理与审计

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `admin_accounts` | `username` | PBKDF2 凭据 |
| `admin_sessions` | `id` | `token_hash`、`expires_at`（8 天）、`revoked_at` |
| `admin_login_throttles` | `username_key` | 管理员登录节流 |
| `admin_audit_log` | `id` | `actor`、`action`、`entity_type`、`entity_id`、`details`(JSON 文本) |
| `content_reports` | `id` | `reporter_id`、`target_type`、`target_id`、`reason`、`status` ∈ open/resolved/dismissed |

### 邀请与邮箱（ADR-021）

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `invite_codes` | `id` | `code_hash`（UNIQUE，SHA-256）、`source`（user/admin）、`issued_by`（可空）、`issued_month`（`YYYY-MM`，Asia/Shanghai）、`used_by`（不设外键：领取发生在用户行写入之前）、`used_at` |
| `user_emails` | `user_id` | `email`（UNIQUE，小写），`created_at`。邮箱不验证，不对外公开 |

### 通知与 CAS 流程

| 表 | 主键 | 说明 |
| --- | --- | --- |
| `notifications` | `id` | `recipient_id`、`actor_id`、`kind`、`title`、`body`、`target_path`、`read_at` |
| `cas_login_states` | `state_hash` | 浏览器 CAS 的 state（5 分钟，一次性 `used_at`） |
| `cas_login_codes` | `code_hash` | CAS 结果换取的一次性 code（2 分钟，存 `student_id_hash`） |
| `cas_password_challenges` | `challenge_hash` | 验证码挑战（流程已停用，表保留）：`student_id_hash`、`encrypted_state`（AES-GCM 密文，用后清空）、`consumed_at`、`attempt_count`（上限 3） |

## 安全相关的数据约定

- 所有令牌、挑战 ID、code 都只保存 SHA-256 哈希。
- 历史学号只保存 HMAC；新账户不再采集学号。任何表中都没有学号明文或真实姓名。
- `cas_password_challenges.encrypted_state` 在完成或失败后被置为空字符串。
- 外键启用：本地 `PRAGMA foreign_keys = ON`；D1 默认启用。删除用户会级联删除其课程、作业、会话、好友请求等，但 `assignments.course_id` 为 `SET NULL`。
