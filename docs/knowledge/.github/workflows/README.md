# .github/workflows — CI 流水线

文件：`.github/workflows/ci.yml`（名称 `CI`）。

## 触发条件

- `push` 到 `main`
- `pull_request`（所有分支）
- `workflow_dispatch`（手动）

并发控制：同一工作流同一引用只保留最新一次运行（`cancel-in-progress: true`）。权限仅 `contents: read`。

## 单个作业：`verify`（API, admin, and Flutter Web）

运行环境 `ubuntu-latest`，超时 30 分钟。按顺序执行：

| 步骤 | 命令 / 动作 | 目的 |
| --- | --- | --- |
| 检出 | `actions/checkout@v4` | 获取代码 |
| Node 22 | `actions/setup-node@v4` | API 运行时 |
| pnpm 11.28.4 | `pnpm/action-setup@v4` | 与根 `packageManager` 一致 |
| 安装 | `pnpm install --frozen-lockfile` | 锁定依赖 |
| API 类型检查 | `pnpm check` | `tsc --noEmit` |
| API 测试 | `pnpm test` | Vitest |
| API 构建 | `pnpm build` | `tsc` |
| 管理台语法 | `node --check apps/admin/admin.js` | 仅语法，没有 UI 测试 |
| Flutter 稳定版 | `subosito/flutter-action@v2`，开启缓存 | 客户端工具链 |
| 依赖 | `flutter pub get`（`apps/mobile`） | |
| 格式 | `dart format --output=none --set-exit-if-changed lib test` | 格式不符即失败 |
| 分析 | `flutter analyze` | |
| 测试 | `flutter test` | 31 个 widget 测试 |
| Web 构建 | `flutter build web --release` | 产物 `apps/mobile/build/web` |

## 不在 CI 中的内容

- Android APK/AAB 构建（`AGENT.md` 规定当前迭代暂不进入 CI）。
- 迁移的远程执行（`wrangler d1 migrations apply` 需要账号凭据，不得放入公开 CI）。
- 部署（生产 `AUTH_MODE=disabled`，未开放注册，禁止自动部署）。
- 端到端浏览器测试。

## 注意事项

- CI 没有配置 `PUB_HOSTED_URL` 等镜像变量；若依赖下载在 CI 中失败，应显式配置，而不是禁用 TLS。
- 工作流不注入任何 secret。新增需要密钥的步骤时，应使用 GitHub Secrets 且不得打印其值。
- `AGENT.md` 的“Required Verification”章节与本工作流一致；修改任一方时请同步另一方。
