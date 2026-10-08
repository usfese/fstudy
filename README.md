# FStudy

面向北京邮电大学学生的课业与轻社交应用。当前仓库包含首个可运行的后端纵向切片：

- Hono API，同一份业务代码运行于 Node.js 和 Cloudflare Workers
- 本地 `node:sqlite` 与生产 Cloudflare D1
- 开发环境学生身份验证器（不会连接学校认证）
- 注册、登录、个人资料、标签、手动课表和待交作业
- OpenAPI 文档端点

## 本地启动

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

## 当前接口

- `POST /v1/auth/register`、`POST /v1/auth/login`、`POST /v1/auth/logout`
- `GET/PATCH /v1/me`、`PUT /v1/me/tags`
- `GET /v1/tags`
- `GET/POST /v1/courses`
- `GET/POST /v1/assignments`
- `PATCH /v1/assignments/:id/completion`
- `GET/POST /v1/projects`、`PATCH /v1/projects/:id/status`
- `POST /v1/projects/:id/applications`
- `GET/PATCH /v1/project-applications[/:id]`
- `GET/POST /v1/forum/posts`
- `GET /v1/forum/posts/:id`、`POST /v1/forum/posts/:id/replies`

除注册、登录、健康检查和 OpenAPI 文档外，业务接口使用 `Authorization: Bearer <token>`。API 默认对敏感响应设置 `Cache-Control: no-store`，并仅允许 `ALLOWED_ORIGINS` 中列出的浏览器来源。

## Flutter

Flutter 客户端当前支持 Web/PWA 与 Android 工程结构；本阶段以 Web 构建、静态检查和行为测试作为验证门槛。
