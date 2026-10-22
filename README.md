# FStudy

面向北京邮电大学学生的课业与轻社交应用。当前仓库包含首个可运行的后端纵向切片：

- Hono API，同一份业务代码运行于 Node.js 和 Cloudflare Workers
- 本地 `node:sqlite` 与生产 Cloudflare D1
- 用户名 + 邀请码注册（每人每月可生成 5 个邀请码）与邮箱记录；不验证学生身份（ADR-021）
- 注册、登录、个人资料、全局标签（用户可创建与搜索）、手动课表和待交作业
- 学生会话保留 30 天；Web 端登录令牌存于本地安全存储，产品更新/重新部署不会清除登录状态（仅服务端明确返回 401 时清除）
- 管理控制台：邀请码生成与复制、用户/内容/举报/标签管理、操作审计
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

注册需要邀请码。本地没有预置邀请码，先用运营账号生成一个（需要已配置 `ADMIN_BOOTSTRAP_USERNAME` 与 `ADMIN_BOOTSTRAP_PASSWORD`）：

```bash
TOKEN=$(curl -s -X POST http://localhost:8787/v1/admin/auth/login -H 'content-type: application/json' \
  -d '{"username":"operator","password":"<ADMIN_BOOTSTRAP_PASSWORD>"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).accessToken')
CODE=$(curl -s -X POST http://localhost:8787/v1/admin/invites -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).code')
```

然后注册（用户名 3–20 位字母、数字或下划线；邮箱会被记录但不验证）：

```bash
curl -X POST http://localhost:8787/v1/auth/register -H 'content-type: application/json' \
  -d "{\"username\":\"student01\",\"email\":\"student@example.edu\",\"appPassword\":\"correct-horse-battery\",\"departmentId\":\"computer\",\"inviteCode\":\"$CODE\"}"
```

响应中的 `accessToken` 作为后续请求的 Bearer Token。

## Cloudflare 部署

生产环境已于 2026-10-22 部署，地址与当前配置见上文“生产环境”。重新部署时：

1. 确认 `apps/api/wrangler.jsonc` 中的 D1 `database_id` 与 `ALLOWED_ORIGINS` 指向当前生产资源。
2. 写入不可公开且长度充足的 `STUDENT_ID_PEPPER`（仅保留给已停用的 CAS 兼容代码；新账户不使用学号）：

   ```bash
   pnpm --filter @fstudy/api exec wrangler secret put STUDENT_ID_PEPPER
   ```

3. 执行远程迁移：`pnpm db:migrate:remote`（只追加，不修改已部署迁移）。
4. 使用 Node 22 部署 API：`pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy`（在 `apps/api` 下）。
5. 构建学生 Web：`flutter build web --release --dart-define=API_BASE_URL=https://fstudy-api.a07450865.workers.dev`。
6. 部署学生 Web Worker：`pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy --config ../mobile/wrangler.jsonc`（在 `apps/api` 下）。
7. 部署管理台：`pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js pages deploy ../admin --project-name fstudy-admin --branch main`。

生产环境通过邀请码开放注册（`INVITE_REGISTRATION_ENABLED=true`），没有邀请码仍无法创建账户。

### 北邮 CAS（已停用）

当前不验证学生身份（ADR-021）。浏览器跳转式 CAS 因北邮拒绝服务授权而关闭（`CAS_LOGIN_ENABLED` 未开启）。验证码与学校密码流程已注释停用，相关代码仍保留在仓库中，恢复前需要新的明确批准和安全评审。第三方库 [byrdocs/bupt-auth](https://github.com/byrdocs/bupt-auth) 不是官方接口，本仓库没有引入其代码，其 UCloud token 与角色流程不使用。

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

- 认证：`POST /v1/auth/register`（需要邀请码与邮箱）、`/login`、`/logout`；北邮 CAS：`/v1/auth/cas/*`（浏览器登录，已关闭）；验证码路由已注释停用
- 邀请码：`GET/POST /v1/me/invites`（每人每月 5 个）；运营：`POST /v1/admin/invites`
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

GitHub Actions 在推送到 `main`、Pull Request 和手动触发时执行 API 类型检查/测试/构建、后台 JavaScript 语法与请求行为测试，以及 Flutter 格式检查、分析、行为测试和 Web Release 构建。Android 打包暂不进入 CI，遵循当前 Web 优先迭代约束。

本地 SQLite 开发入口会自动应用 `0001`–`0015` 迁移；Cloudflare D1 生产部署需显式执行 `pnpm db:migrate:remote`。预发迁移和部署状态见 `docs/knowledge/apps/api/migrations/README.md` 与 `AGENT.md`。

## 生产环境（2026-10-22 已部署）

| 用途 | 地址 |
| --- | --- |
| 学生 Web | `https://fstudy-web.a07450865.workers.dev` |
| API | `https://fstudy-api.a07450865.workers.dev` |
| 管理控制台 | `https://fstudy-admin.pages.dev` |
| 预发 Web | `https://fstudy-student-staging.pages.dev` |
| 预发 API | `https://fstudy-api-staging.a07450865.workers.dev` |

- 生产 D1：`fstudy`（`a0fb31d4-6d34-42db-9895-daf724d8bd25`），迁移 `0001`–`0015` 已执行。
- 注册仍需邀请码；`INVITE_REGISTRATION_ENABLED=true`。
- 生产管理员账号为 `operator`，初始密码保存在仓库外的 `~/.fstudy/production-admin.txt`（权限 `0600`）。首次登录后请立即改密码。
- 学生 Web 使用 Workers 静态资源（`apps/mobile/wrangler.jsonc`，SPA 回退）。`fstudy-student.pages.dev` 的 Pages 直传在该账号持续卡在 `upsert-hashes`，**该地址未使用**。
- 当前 Wrangler 在 Node 26 上会对部分 Cloudflare API 挂起；部署时使用 Node 22：`pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js ...`。

## Android 打包与签名

签名材料**不要提交到 Git**。`apps/mobile/android/key.properties`、`*.jks`、`*.keystore` 已在 `.gitignore` 中。

首次创建上传密钥（务必离线备份；丢失后无法更新已发布应用）：

```bash
cd apps/mobile
keytool -genkeypair -v \
  -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias fstudy
cp android/key.properties.example android/key.properties
# 编辑 android/key.properties，填入真实密码与 storeFile=upload-keystore.jks
```

构建 Release APK（必须指定 API 地址，否则 Android 会回退到模拟器地址 `http://10.0.2.2:8787`）：

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://fstudy-api.a07450865.workers.dev
```

产物：`apps/mobile/build/app/outputs/flutter-apk/app-release.apk`。

按 ABI 拆分或构建 AAB：

```bash
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://fstudy-api.a07450865.workers.dev
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://fstudy-api.a07450865.workers.dev
```

没有 `key.properties` 时构建会自动回退到 debug 签名，仅用于本地 `flutter run --release`，**不能发布**。主 Manifest 已声明 `INTERNET` 权限，Release 构建可以联网。

## 上传到 GitHub

仓库已包含 `.gitignore`、GitHub Actions CI 和知识库校验。上传前确认没有真实密钥：

```bash
git status
git grep -nE "STUDENT_ID_PEPPER=.+|ADMIN_BOOTSTRAP_PASSWORD=.+|storePassword=.+" -- . ':!*.example'
```

推送到空仓库：

```bash
git remote add origin git@github.com:<你的账号>/<仓库名>.git
git branch -M main
git push -u origin main
```

CI 会执行 API 检查/测试/构建、知识库校验、管理台语法与请求行为测试，以及 Flutter 格式检查、分析、会话持久化单元测试、组件测试和 Web Release 构建。Cloudflare 部署凭据不要写进仓库，应放在 GitHub Actions Secrets（当前工作流不自动部署）。

## 生产维护检查表

- [x] 创建生产 D1 `fstudy` 并写入 `database_id`
- [x] 写入 secrets：`STUDENT_ID_PEPPER`、`ADMIN_BOOTSTRAP_USERNAME`、`ADMIN_BOOTSTRAP_PASSWORD`
- [x] 设置 `ALLOWED_ORIGINS` 与 `INVITE_REGISTRATION_ENABLED`
- [x] 执行生产迁移 `0001`–`0015`
- [x] 部署 API Worker `fstudy-api`
- [x] 构建并部署学生 Web Worker `fstudy-web`
- [x] 部署管理控制台 `fstudy-admin`
- [ ] 首次登录管理台后修改 `operator` 密码
- [ ] 用真实 keystore 构建并签名 Android Release APK，离线备份 keystore 与密码
- [ ] 定期备份生产 D1
