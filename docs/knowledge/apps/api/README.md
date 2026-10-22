# apps/api — API 包根目录

包名 `@fstudy/api`，TypeScript ESM，基于 Hono。同一份业务代码运行在本地 Node.js（`node:sqlite`）和 Cloudflare Workers（D1）。

## 目录结构

```
apps/api/
├── src/
│   ├── core/          共享类型、错误、安全原语      → core/README.md
│   ├── adapters/      D1 / node:sqlite / 学生验证器 → adapters/README.md
│   ├── entrypoints/   node.ts、worker.ts            → entrypoints/README.md
│   ├── http/          路由与中间件、接口定义         → http/README.md
│   └── modules/       业务模块                      → modules/README.md
├── migrations/        SQL 迁移 0001–0013            → migrations/README.md
├── test/              Vitest 测试                   → test/README.md
├── wrangler.jsonc         生产配置（占位，未部署）
├── wrangler.staging.jsonc 预发配置（已部署）
└── .dev.vars.example      本地环境变量示例
```

## 依赖

| 包 | 用途 |
| --- | --- |
| `hono` | HTTP 框架，含 `cors`、`secure-headers`、`body-limit` 中间件 |
| `@hono/zod-openapi`、`zod` | 请求校验与 Schema 定义（`http/schemas.ts`） |
| `@hono/zod-validator` | `zValidator('json' \| 'query', Schema)` 包装 |
| `@hono/node-server` | Node 运行时 |
| `wrangler`、`@cloudflare/workers-types` | Workers/D1 开发与部署 |
| `tsx`、`typescript`、`vitest` | 本地运行、类型检查、测试 |

## 脚本（`apps/api/package.json`）

| 脚本 | 作用 |
| --- | --- |
| `pnpm dev` | `tsx watch src/entrypoints/node.ts`，默认监听 `http://localhost:8787` |
| `pnpm check` | `tsc --noEmit` |
| `pnpm test` | `vitest run` |
| `pnpm build` | `tsc -p tsconfig.json`，产物到 `dist/` |
| `pnpm db:migrate:local` | `wrangler d1 migrations apply fstudy --local` |
| `pnpm db:migrate:remote` | `wrangler d1 migrations apply fstudy --remote` |
| `pnpm --filter @fstudy/api deploy` | `wrangler deploy`（**生产配置，禁止在未完成安全评审前执行**） |

根 `package.json` 提供同名的转发脚本（`pnpm dev`、`pnpm check`、`pnpm test`、`pnpm build`、`pnpm db:migrate:*`）。

## 环境变量与配置

| 变量 | 本地 Node | Workers | 说明 |
| --- | --- | --- | --- |
| `FSTUDY_DB_PATH` | 可选，默认 `./fstudy.sqlite` | — | 本地 SQLite 文件路径（已在 `.gitignore`） |
| `PORT` | 可选，默认 `8787` | — | 监听端口 |
| `INVITE_REGISTRATION_ENABLED` | 默认开启（设为 `false` 才关闭） | 默认关闭（设为 `true` 才开启）；生产不设置 | 是否允许注册（需要邀请码，ADR-021） |
| `STUDENT_ID_PEPPER` | 可选；生产 `NODE_ENV=production` 时必须 ≥ 32 字符 | **必须**（secret），< 32 字符时返回 503 | 历史学号 HMAC 密钥；新账户不使用 |
| `ALLOWED_ORIGINS` | 默认包含 `127.0.0.1/localhost` 的 8080 与 8081 | `vars` | CORS 白名单，逗号分隔，禁止 `*` |
| `CAS_LOGIN_ENABLED` | `true` 才开启 | `vars` | 浏览器跳转式 CAS（当前因北邮拒绝服务授权而关闭） |
| `CAS_CALLBACK_URL` | 可选 | `vars` | 必须是 `https://`，不带 query/hash/凭据 |
| `ADMIN_BOOTSTRAP_USERNAME` / `ADMIN_BOOTSTRAP_PASSWORD` | 可选 | 可选 secret | 首次启动时创建管理员；已存在管理员则忽略 |

`AUTH_MODE`、`SCHOOL_PASSWORD_REGISTRATION_ENABLED`、`CAS_STATE_ENCRYPTION_KEY` 已不被代码读取（ADR-021）。验证码与学校验证代码已注释，见 [adapters/README.md](./src/adapters/README.md)。

## 部署配置

- `wrangler.jsonc`（生产）：`name: fstudy-api`，D1 为 `fstudy`（`a0fb31d4-6d34-42db-9895-daf724d8bd25`），`ALLOWED_ORIGINS=https://fstudy-web.a07450865.workers.dev,https://fstudy-admin.pages.dev`，`INVITE_REGISTRATION_ENABLED=true`（注册仍需邀请码），`CAS_LOGIN_ENABLED=false`。已部署到 `https://fstudy-api.a07450865.workers.dev`（2026-10-22）。
- `wrangler.staging.jsonc`（预发）：`name: fstudy-api-staging`，`workers_dev: true`，`INVITE_REGISTRATION_ENABLED: true`，`CAS_LOGIN_ENABLED: false`；`AUTH_MODE` 与学校验证开关已注释。D1 库 `fstudy-staging`，允许来源 `https://fstudy-student-staging.pages.dev`。
- 两份配置共用 `main: src/entrypoints/worker.ts` 与 `migrations_dir: migrations`。
- 不要提交 `.dev.vars`、`.env`、任何 secret 值。

## 当前工作区状态

- 本包内有未提交改动，涉及 `notifications` 模块、CAS 浏览器登录与验证码（已抽到 `modules/identity/cas-login-service.ts`）、`0010`–`0013` 迁移。
- `dist/`、`.wrangler/`、`node_modules/` 为生成物，已在 `.gitignore`。

## 待确认 / 已知问题

1. `node.ts` 的本地迁移不使用迁移记录表，而是按“标志表/索引是否存在”判断（见 [ADR-017](../../decisions.md#adr-017数据库迁移只允许前向变更)）。
2. OpenAPI 文档为手写 summary，路径已与路由一致；请求/响应 Schema 尚未生成（见 [http/README.md](./src/http/README.md#openapi-覆盖情况)）。
3. 预发远程迁移已核对，与仓库一致（2026-10-14），详见 [migrations/README.md](./migrations/README.md)。
