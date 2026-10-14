# FStudy

面向北京邮电大学学生的课业与轻社交应用。当前仓库包含首个可运行的后端纵向切片：

- Hono API，同一份业务代码运行于 Node.js 和 Cloudflare Workers
- 本地 `node:sqlite` 与生产 Cloudflare D1
- 开发环境学生身份验证器（不会连接学校认证）
- 注册、登录、个人资料、标签、手动课表和待交作业
- OpenAPI 文档端点

## 本地启动

项目知识库位于 `docs/knowledge/`，修改代码前后请参考并同步更新（见 `AGENT.md` 的 Knowledge Base Protocol）。运行 `pnpm knowledge:check` 校验。

需要 Node.js 22+ 与 pnpm。

```bash
pnpm install
pnpm db:migrate:local
pnpm dev
```

API 默认监听 `http://localhost:8787`，OpenAPI 文档位于 `/openapi.json`。

开发注册使用任意 8–12 位数字学号，学校认证测试密码固定为 `dev-password`。此验证器只能在 `AUTH_MODE=dev` 时运行。

```bash
curl -X POST http://localhost:8787/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"studentId":"20260001","schoolPassword":"dev-password","appPassword":"correct-horse-battery","displayName":"测试同学","departmentId":"computer"}'
```

响应中的 `accessToken` 作为后续请求的 Bearer Token。

## Cloudflare 部署

1. 创建数据库：`pnpm --filter @fstudy/api exec wrangler d1 create fstudy`。
2. 在 `apps/api/wrangler.jsonc` 中填写返回的 D1 `database_id`。
3. 写入不可公开且长度充足的学号哈希 pepper：

   ```bash
   pnpm --filter @fstudy/api exec wrangler secret put STUDENT_ID_PEPPER
   ```

4. 将 `apps/api/wrangler.jsonc` 中的 `ALLOWED_ORIGINS` 替换为实际 Web 来源（例如 `https://app.example.com`）。不要使用 `*`。
5. 执行 `pnpm db:migrate:remote`。
6. 配置生产认证方式后再部署：`pnpm --filter @fstudy/api deploy`。

生产环境默认拒绝注册；真实 BUPT 验证尚未启用，避免在未完成安全和网络验证前接触真实统一认证密码。

### BUPT CAS-only 验证（实验性）

API 提供实验性的 `AUTH_MODE=bupt-cas` 验证器，只使用 `auth.bupt.edu.cn` 的 CAS 登录与 `serviceValidate`，不请求 ucloud token/角色接口。学校密码只在注册请求内存中用于这次验证，不写日志、不保存；学号仍只保存 HMAC，姓名不落库。验证码暂不支持，CAS 要求验证码时会安全失败并提示稍后处理。部署到公网前仍需确认学校允许此类集成，并完成真实网络、隐私告知和安全评审。此模式不得用于生产开放注册。

第三方库参考：[byrdocs/bupt-auth](https://github.com/byrdocs/bupt-auth)，其 MIT 许可；FStudy 没有引入该库代码，CAS-only 流程由本仓库适配器独立实现。第三方库的 ucloud token/角色流程不使用。

## 管理控制台（本地开发）

管理台是独立的静态 Web 应用，位于 `apps/admin`，不会复用学生端登录会话。首次启动 API 时，可通过环境变量创建首个管理员；密码至少 14 位，服务端只保存 PBKDF2 哈希。管理员首次创建后，更改环境变量不会覆盖已有账号，可在管理台内修改密码。

```bash
ADMIN_BOOTSTRAP_USERNAME=operator \
ADMIN_BOOTSTRAP_PASSWORD='use-a-unique-password-of-14-chars-or-more' \
pnpm dev
```

另开终端启动静态后台，访问 `http://127.0.0.1:8081`：

```bash
python3 -m http.server 8081 --bind 127.0.0.1 --directory apps/admin
```

生产部署时，应将 `apps/admin` 部署到独立的管理域名，并通过 HTTPS 访问；API `ALLOWED_ORIGINS` 需要显式允许此管理域名。使用 Wrangler secret 配置 `ADMIN_BOOTSTRAP_PASSWORD`，并配置 `ADMIN_BOOTSTRAP_USERNAME`。学生 Bearer token 与管理 API 的独立会话互不通用。管理员登录 token 只存于当前标签页的 `sessionStorage`，有效期 8 天，支持退出撤销与密码轮换。

若管理前端和 API 不同源，部署方需在 `apps/admin/index.html` 的模块脚本之前设置 `window.FSTUDY_API_URL = 'https://api.example.com'`，并在 API CORS 白名单中加入管理台域名。

管理 API 目前提供运营统计、用户搜索及封禁/恢复、讨论/回复/组队内容隐藏或删除、举报受理、受控标签维护和操作审计。封禁用户会关闭其发现展示并立即撤销现有学生会话。对外发布前仍需配置 HTTPS、管理域访问限制与备份策略。

## 当前接口

完整的请求/响应定义见 [docs/knowledge/apps/api/src/http/README.md](docs/knowledge/apps/api/src/http/README.md)。主要分组如下：

- 认证：`POST /v1/auth/register`、`/login`、`/logout`；北邮 CAS：`/v1/auth/cas/*`、`/v1/auth/cas/password/*`（预发实验，默认关闭）
- 个人资料与设置：`GET/PATCH /v1/me`、`GET/PUT /v1/me/academic-settings`、`GET/PUT /v1/me/tags`、`GET /v1/tags`（需要登录）
- 课表与学习：`GET/POST /v1/courses`、`GET/POST /v1/assignments`、`PATCH /v1/assignments/:id/completion`、`GET/POST /v1/plans`、`PATCH /v1/plans/:id/completion`
- 社交：`GET /v1/discover`、`GET /v1/friends`、`POST /v1/friend-requests`、`PATCH /v1/friend-requests/:id`、`GET /v1/availability`、`GET/POST /v1/availability-invites`、`PATCH /v1/availability-invites/:id`
- 组队：`GET/POST /v1/projects`、`PATCH /v1/projects/:id/status`、`POST /v1/projects/:id/applications`、`GET/PATCH /v1/project-applications[/:id]`
- 讨论区：`GET/POST /v1/forum/posts`、`GET /v1/forum/posts/:id`、`POST /v1/forum/posts/:id/replies`
- 通知与举报：`GET /v1/notifications`、`POST /v1/notifications/read`、`POST /v1/reports`
- 独立管理员 API：`/v1/admin/*`（登录、总览、用户、内容、举报、标签、审计）

除注册、登录、CAS 入口、管理员登录、健康检查和 OpenAPI 文档外，业务接口使用 `Authorization: Bearer <token>`。API 默认对敏感响应设置 `Cache-Control: no-store`，并仅允许 `ALLOWED_ORIGINS` 中列出的浏览器来源。

## Flutter

Flutter 客户端当前支持 Web/PWA 与 Android 工程结构；本阶段以 Web 构建、静态检查和行为测试作为验证门槛。

GitHub Actions 在推送到 `main`、Pull Request 和手动触发时执行 API 类型检查/测试/构建、后台 JavaScript 语法检查，以及 Flutter 格式检查、分析、行为测试和 Web Release 构建。Android 打包暂不进入 CI，遵循当前 Web 优先迭代约束。

本地 SQLite 开发入口会自动应用 `0001`–`0013` 迁移（远程预发历史与仓库文件的一致性见 `docs/knowledge/apps/api/migrations/README.md`）；Cloudflare D1 生产部署需显式执行 `pnpm db:migrate:remote`。
