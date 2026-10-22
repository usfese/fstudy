# apps/api/src/entrypoints — 启动入口

入口文件只做三件事：选择适配器、读取环境变量、调用 `createApp`。不得在这里加入业务规则。

## `node.ts`（本地开发）

启动流程（顺序敏感）：

1. 打开 `FSTUDY_DB_PATH`（默认 `./fstudy.sqlite`）的 `NodeSqliteDatabase`。
2. **手动迁移**：对 `0001` 至 `0015` 逐个检测标志表或索引是否存在，不存在才执行对应 SQL。
   - 标志表：`users`、`plans`、`friend_requests`、`availability_invites`、`auth_throttles`、`projects`、`forum_posts`、`admin_sessions`、`user_academic_settings`、`notifications`、`cas_login_states`、`cas_password_challenges`、`invite_codes`。
   - `0013` 通过索引 `cas_password_challenges_attempts_idx` 判断；`0015` 通过索引 `users_username_unique` 判断。
3. 检查 `STUDENT_ID_PEPPER`：`NODE_ENV=production` 时长度必须 ≥ 32，否则启动失败。
4. `AdminService.bootstrap()`：有管理员则跳过；无管理员且提供了环境变量则创建。失败时关闭数据库并抛出。
5. `createApp(dependencies)`，`serve({ fetch, port })`，监听 `SIGINT` / `SIGTERM` 优雅退出。

已停用（ADR-021）：验证码相关的 `SCHOOL_PASSWORD_REGISTRATION_ENABLED` 与 `CAS_STATE_ENCRYPTION_KEY` 检查已注释，学生验证器不再构造。

依赖 `inviteRegistrationEnabled: process.env.INVITE_REGISTRATION_ENABLED !== 'false'`，即本地默认开启。

默认 `ALLOWED_ORIGINS` 为 `http://127.0.0.1:8080,http://localhost:8080,http://127.0.0.1:8081,http://localhost:8081`。

## `worker.ts`（Cloudflare Workers）

- 导出 `default { fetch(request, env) }`，每个请求都会构造依赖（`D1SqlDatabase(env.DB)`）。
- 启动前校验（失败返回 503 `service_misconfigured`，不泄露具体配置）：`STUDENT_ID_PEPPER` 缺失或少于 32 字符。
- 管理员引导：仅当提供了 `ADMIN_BOOTSTRAP_USERNAME` 或 `ADMIN_BOOTSTRAP_PASSWORD` 时执行，结果以 `Promise` 缓存于模块作用域；失败会清空缓存并返回 503 `管理员配置无效`。
- 注册开关：`inviteRegistrationEnabled: env.INVITE_REGISTRATION_ENABLED === 'true'`，即**默认关闭**。`wrangler.staging.jsonc` 设为 `true`；`wrangler.jsonc`（生产）不设置。
- 迁移不在 Worker 中执行，需由 `pnpm db:migrate:remote` 显式完成。

## 两者的差异

| 项 | `node.ts` | `worker.ts` |
| --- | --- | --- |
| 数据库 | `NodeSqliteDatabase` | `D1SqlDatabase` |
| 迁移 | 启动时自动（手动检测） | 手动 `wrangler d1 migrations apply` |
| `ALLOWED_ORIGINS` 默认 | 本地 8080/8081 | 空（必须配置） |
| 注册开关 `INVITE_REGISTRATION_ENABLED` 默认 | 开启（除非设为 `false`） | 关闭（必须设为 `true`） |
| `AUTH_MODE` | 已不读取 | 已不读取 |

## 相关决策

- [ADR-001](../../../../decisions.md#adr-001api-使用-hono--typescript同一份业务代码同时运行于-nodejs-与-cloudflare-workers)：单一业务代码，两个入口。
- [ADR-017](../../../../decisions.md#adr-017数据库迁移只允许前向变更)：迁移策略及本地检测方式。
- [ADR-021](../../../../decisions.md#adr-021邀请码注册记录邮箱停用学生身份验证)：注册开关与学生验证停用。
