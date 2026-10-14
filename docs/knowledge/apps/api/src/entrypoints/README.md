# apps/api/src/entrypoints — 启动入口

入口文件只做三件事：选择适配器、读取环境变量、调用 `createApp`。不得在这里加入业务规则。

## `node.ts`（本地开发）

启动流程（顺序敏感）：

1. 打开 `FSTUDY_DB_PATH`（默认 `./fstudy.sqlite`）的 `NodeSqliteDatabase`。
2. **手动迁移**：对 `0001` 至 `0013` 逐个检测“标志表/列”是否存在，不存在才执行对应 SQL。
   - 标志表：`users`、`plans`、`friend_requests`、`availability_invites`、`auth_throttles`、`projects`、`forum_posts`、`admin_sessions`、`user_academic_settings`、`notifications`、`cas_login_states`、`cas_password_challenges`。
   - `0013` 通过检测索引 `cas_password_challenges_attempts_idx` 是否存在来决定是否执行（它只创建索引）。
3. 检查 `STUDENT_ID_PEPPER`：`NODE_ENV=production` 时长度必须 ≥ 32，否则启动失败。
4. 检查 CAS 配置：`SCHOOL_PASSWORD_REGISTRATION_ENABLED=true` 且 `AUTH_MODE=bupt-cas` 时，`CAS_STATE_ENCRYPTION_KEY` 必须 ≥ 32 字符。
5. 按 `AUTH_MODE` 选择 `StudentVerifier`：`dev` → `DevelopmentStudentVerifier`，`bupt-cas` → `BuptCasStudentVerifier`，其余 → `DisabledStudentVerifier`。
6. `AdminService.bootstrap()`：有管理员则跳过；无管理员且提供了环境变量则创建。失败时关闭数据库并抛出。
7. `createApp(dependencies)`，`serve({ fetch, port })`，监听 `SIGINT` / `SIGTERM` 优雅退出。

默认 `ALLOWED_ORIGINS` 为 `http://127.0.0.1:8080,http://localhost:8080,http://127.0.0.1:8081,http://localhost:8081`。

## `worker.ts`（Cloudflare Workers）

- 导出 `default { fetch(request, env) }`，每个请求都会构造依赖（`D1SqlDatabase(env.DB)`），开销较小但需注意不要在模块作用域外保存请求级状态。
- 启动前校验（失败返回 503 `service_misconfigured`，**不会泄露具体配置**）：
  - `STUDENT_ID_PEPPER` 缺失或少于 32 字符。
  - `SCHOOL_PASSWORD_REGISTRATION_ENABLED=true` 且 `AUTH_MODE=bupt-cas` 时 `CAS_STATE_ENCRYPTION_KEY` 无效。
- 管理员引导：仅当提供了 `ADMIN_BOOTSTRAP_USERNAME` 或 `ADMIN_BOOTSTRAP_PASSWORD` 时执行，结果以 `Promise` 缓存于模块作用域；失败会清空缓存并返回 503 `管理员配置无效`。
- 迁移不在 Worker 中执行，需由 `pnpm db:migrate:remote` 显式完成。

## 两者的差异

| 项 | `node.ts` | `worker.ts` |
| --- | --- | --- |
| 数据库 | `NodeSqliteDatabase` | `D1SqlDatabase` |
| 迁移 | 启动时自动（手动检测） | 手动 `wrangler d1 migrations apply` |
| `ALLOWED_ORIGINS` 默认 | 本地 8080/8081 | 空（无默认，必须配置） |
| `schoolPasswordRegistrationEnabled` | `dev` 或显式 `true` | `dev` 或显式 `true` |
| 未配置的 `AUTH_MODE` | 视为 `dev` | 视为 `disabled`（`DisabledStudentVerifier`） |

最后一行是两者的重要行为差异：本地未设置 `AUTH_MODE` 时默认启用开发验证器，而 Workers 上未设置时默认关闭注册。

## 相关决策

- [ADR-001](../../../../decisions.md#adr-001api-使用-hono--typescript同一份业务代码同时运行于-nodejs-与-cloudflare-workers)：单一业务代码，两个入口。
- [ADR-017](../../../../decisions.md#adr-017数据库迁移只允许前向变更)：迁移策略及本地检测方式。
