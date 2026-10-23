# FStudy

面向北京邮电大学学生的课业与轻社交应用。FStudy 把课表、作业、自定义安排、校园地图、同学发现、讨论区与组队整合在一起，帮助学生更清楚地安排学习，也更容易找到志同道合的伙伴。

- 源码仓库：[github.com/usfese/fstudy](https://github.com/usfese/fstudy)
- 学生 Web：[fstudy.usfese.cc](https://fstudy.usfese.cc)
- API：[fstudy-api.usfese.cc](https://fstudy-api.usfese.cc)
- 管理控制台：[fstudy-admin.usfese.cc](https://fstudy-admin.usfese.cc)
- 预发 Web：[fstudy-staging.usfese.cc](https://fstudy-staging.usfese.cc)
- 预发 API：[fstudy-api-staging.usfese.cc](https://fstudy-api-staging.usfese.cc)

> Web/PWA 与 Android 均为当前发布目标；Android 通过 GitHub Release 直接分发 APK，不使用 Google Play。iOS 工程结构保留但暂不构建。

## 功能

- **邀请制账户**：用户名 + 密码登录，注册需要邀请码；邮箱会被记录但不验证，也不对外展示。不验证学生身份，不索取学校密码。
- **课表管理**：按固定 14 节作息选择上课时间，支持单双周、多时间段、学期起始日、周视图，以及课程编辑、删除和清空。
- **作业与安排**：记录作业截止时间和完成状态，可关联课程；自定义安排支持完成状态与提醒分钟数。
- **校园地图**：按西土城、沙河校区检索常用地点，并可跳转外部地图服务查看路线。
- **发现同学**：通过院系、兴趣与方向标签发现同学，发送好友申请，按课表可见性查询共同空闲时间。
- **社区与组队**：校园讨论区、帖子回复、项目发布、申请加入与举报。
- **站内通知**：好友申请、组队申请等事件的通知与已读状态。
- **运营管理台**：邀请码生成、用户与内容管理、举报处理、受控标签维护和操作审计。

## 技术栈

| 部分 | 技术 |
| --- | --- |
| 客户端 | Flutter（Web/PWA、Android），`go_router`、`dio`、`flutter_secure_storage` |
| API | Hono + TypeScript + Zod，同一份业务代码运行于 Node.js 与 Cloudflare Workers |
| 数据库 | 本地 `node:sqlite`；生产 Cloudflare D1；SQL 迁移只追加 |
| 管理台 | 原生 HTML/CSS/JavaScript 静态应用，无构建步骤，由 Cloudflare Worker 托管 |
| 测试与 CI | Vitest、Node test runner、Flutter Test、GitHub Actions（CI + Android Release） |

## 仓库结构

```text
.
├── apps/
│   ├── api/       Hono API、业务模块、SQL 迁移与测试
│   ├── mobile/    Flutter 客户端（Web/PWA 与 Android）
│   └── admin/     运营管理台静态页面
├── docs/
│   └── knowledge/ 按目录组织的项目知识库与架构决策（ADR）
├── scripts/       知识库校验与版本脚本
├── AGENT.md       仓库工作约定与实现边界
├── CONTRIBUTING.md 分支、验证与发布流程
├── CHANGELOG.md   版本变更记录
└── README.md
```

更详细的模块说明、接口契约和架构决策见 [`docs/knowledge/`](docs/knowledge/)。

## 本地开发

### 环境要求

- Node.js 22+
- pnpm
- Flutter stable（构建客户端时需要）

### 启动 API 与管理台

```bash
pnpm install
pnpm db:migrate:local

# 首次启动时创建管理员；密码至少 14 位
ADMIN_BOOTSTRAP_USERNAME=operator \
ADMIN_BOOTSTRAP_PASSWORD='use-a-unique-password-of-14-chars-or-more' \
pnpm dev
```

API 默认监听 `http://127.0.0.1:8787`，OpenAPI 文档位于 `http://127.0.0.1:8787/openapi.json`。

另开终端启动管理台：

```bash
pnpm admin:dev
```

访问 `http://127.0.0.1:8081`，使用上面的管理员账号登录并生成邀请码。随后在学生端注册时填入该邀请码。管理员密码只保存 PBKDF2 哈希；首次创建后，修改环境变量不会覆盖已有账号。

### 启动 Flutter 客户端

```bash
cd apps/mobile
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

API 地址通过 `--dart-define=API_BASE_URL=...` 注入。默认值：Web 为 `http://127.0.0.1:8787`，Android 模拟器为 `http://10.0.2.2:8787`。真机调试需要可访问的局域网地址或 `adb reverse`。

## 配置

主要环境变量：

| 变量 | 说明 |
| --- | --- |
| `FSTUDY_DB_PATH` | 本地 SQLite 文件路径，默认 `apps/api/fstudy.sqlite` |
| `PORT` | 本地 API 监听端口，默认 `8787` |
| `INVITE_REGISTRATION_ENABLED` | 是否允许邀请码注册；Workers 环境需要显式设为 `true` |
| `ALLOWED_ORIGINS` | CORS 白名单，逗号分隔，禁止使用 `*` |
| `ADMIN_BOOTSTRAP_USERNAME` | 首次启动时创建的管理员用户名 |
| `ADMIN_BOOTSTRAP_PASSWORD` | 首次启动时创建的管理员密码，至少 14 位 |
| `STUDENT_ID_PEPPER` | 历史学号 HMAC 密钥；新账户不再使用学号 |
| `CAS_LOGIN_ENABLED` | 浏览器 CAS 登录开关，当前关闭 |

请勿提交 `.env`、`.dev.vars`、数据库文件、签名密钥、`key.properties` 或任何密码。生产密钥应通过 Cloudflare Wrangler secret 或 GitHub Actions Secrets 管理。

## 验证

后端：

```bash
pnpm check
pnpm test
pnpm build
```

Flutter：

```bash
cd apps/mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release \
  --dart-define=API_BASE_URL=https://fstudy-api.usfese.cc
```

文档：

```bash
pnpm knowledge:check
```

GitHub Actions 会在推送到 `main`、Pull Request 和手动触发时执行后端检查/测试/构建、管理台测试、知识库校验、Flutter 格式检查/分析/测试/Web Release 构建，以及 Android debug APK 构建。推送 `v*` 标签时还会自动构建并发布 Android APK。

## 开发流程与发布

`main` 是受保护分支，所有改动通过 Pull Request 合并。分支命名、提交约定和完整检查清单见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

发布使用 `vMAJOR.MINOR.PATCH` annotated tag。发布前先更新版本号和构建号：

```bash
pnpm release:version 1.1.0
```

该命令会把 `apps/mobile/pubspec.yaml` 更新为类似 `1.1.0+2` 的形式。更新 `CHANGELOG.md`、合并 PR 后，在 `main` 上打标签并推送：

```bash
git tag -a v1.1.0 -m "FStudy v1.1.0"
git push origin v1.1.0
```

`.github/workflows/release.yml` 会先运行完整 CI，再构建以下产物并创建 GitHub Release：

- 通用 APK
- `arm64-v8a`、`armeabi-v7a`、`x86_64` 分 ABI APK
- `BUILD_INFO.txt`
- `SHA256SUMS.txt`

发布 workflow 会校验 tag 在 `main` 上，并要求 tag 版本与 `pubspec.yaml` 一致。Android 签名密钥通过 GitHub Actions Secrets 注入；本地没有 `key.properties` 时 Release 构建会失败，不会使用 debug 签名。

## 部署

生产环境使用 Cloudflare，自定义域名均位于 `usfese.cc`：

- API：Worker `fstudy-api` + D1 数据库 `fstudy`，域名 `https://fstudy-api.usfese.cc`
- 学生 Web：Worker `fstudy-web` 静态资源，域名 `https://fstudy.usfese.cc`，未知路径回退到 `index.html`
- 管理台：Worker `fstudy-admin` 静态资源，域名 `https://fstudy-admin.usfese.cc`
- 预发 API：Worker `fstudy-api-staging`，域名 `https://fstudy-api-staging.usfese.cc`
- 预发 Web：Worker `fstudy-staging` 静态资源，域名 `https://fstudy-staging.usfese.cc`

重新部署 API 时，在 `apps/api` 下执行：

```bash
# 1. 先执行只追加的远程迁移
pnpm db:migrate:remote

# 2. 部署 API（Wrangler 建议使用 Node 22）
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy
```

预发 API：

```bash
cd apps/api
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy \
  --config wrangler.staging.jsonc
```

构建并部署学生 Web：

```bash
cd apps/mobile
flutter build web --release \
  --dart-define=API_BASE_URL=https://fstudy-api.usfese.cc
cd ../api
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy \
  --config ../mobile/wrangler.jsonc
```

构建并部署预发 Web：

```bash
cd apps/mobile
flutter build web --release --output build/web-staging \
  --dart-define=API_BASE_URL=https://fstudy-api-staging.usfese.cc
cd ../api
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy \
  --config ../mobile/wrangler.staging.jsonc
```

部署管理台（在仓库根目录执行）：

```bash
pnpm dlx node@22 apps/api/node_modules/wrangler/bin/wrangler.js deploy \
  --config wrangler.admin.jsonc
```

部署前请确认 `ALLOWED_ORIGINS` 覆盖实际前端域名，并且没有使用开发环境密钥或占位 D1 配置。自定义域名通过各 `wrangler.jsonc` 的 `routes`（`custom_domain: true`）绑定，证书由 Cloudflare 自动签发。部署管理台前还需确认本地 `apps/admin/config.js` 中的 `FSTUDY_API_URL` 指向生产 API；该文件不提交到 Git。

### Android

Android Release 构建需要项目自己的签名密钥，`apps/mobile/android/key.properties`、`*.jks` 与 `*.keystore` 均不得提交。没有签名配置时 Release 构建会直接失败，不会回退到 debug 签名。本地签名配置模板见 `apps/mobile/android/key.properties.example`；GitHub Actions 使用 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD` 和 `ANDROID_KEY_ALIAS` 四个 Secrets。

项目当前不使用 Google Play，因此 Release 只发布通用 APK 和分 ABI APK，不生成 AAB。安装时优先选择与设备 ABI 匹配的 APK；不确定时使用通用 APK。

## 安全与隐私

- 注册采用邀请制；没有邀请码无法创建账户。
- 邮箱仅记录、不验证，不向其他用户展示。
- 不验证学生身份，不保存学校密码、验证码或学校会话；CAS 登录当前关闭。
- 学生会话有效期 30 天；Web 端令牌保存在本地安全存储中，仅在服务端明确返回 401 时清除。
- 计划备注不会返回给其他用户；好友课表可见性支持完全私密、仅忙闲、显示课程名和完整信息四级。
- 发现安全问题或敏感信息时，请勿在公开 Issue 中粘贴令牌、密码或个人信息，先通过仓库维护者联系。

## 文档与贡献

项目知识库位于 [`docs/knowledge/`](docs/knowledge/)，记录了各模块职责、接口契约与架构决策。修改代码前请阅读 [`AGENT.md`](AGENT.md) 中的工作约定，并在同一变更中同步更新相关文档。

欢迎通过 [GitHub 仓库](https://github.com/usfese/fstudy) 提交 Issue、讨论或 Pull Request。提交代码前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
