# .github/workflows — CI 与发布流水线

本目录包含两个工作流：

- `ci.yml`：Pull Request、`main` 推送和手动触发的验证流水线。
- `release.yml`：`v*` 标签触发的 Android 发布流水线。

## `ci.yml`

名称 `CI`。触发条件：

- `push` 到 `main`
- `pull_request`（所有分支）
- `workflow_dispatch`（手动）
- `workflow_call`（由 `release.yml` 复用）

并发控制：同一工作流同一引用只保留最新一次运行（`cancel-in-progress: true`）。权限仅 `contents: read`。

### 作业 `verify`（API, admin, and Flutter Web）

运行环境 `ubuntu-latest`，超时 30 分钟。按顺序执行：

| 步骤 | 命令 / 动作 | 目的 |
| --- | --- | --- |
| 检出 | `actions/checkout@v4` | 获取代码 |
| Node 22 | `actions/setup-node@v4` | API 运行时 |
| pnpm 11.28.4 | `pnpm/action-setup@v4` | 与根 `packageManager` 一致 |
| 安装 | `pnpm install --frozen-lockfile` | 锁定依赖 |
| 知识库 | `node scripts/knowledge-check.mjs --strict` | 文档完整性 |
| API 类型检查 | `pnpm check` | `tsc --noEmit` |
| API 测试 | `pnpm test` | Vitest + 管理台 Node `vm` 测试 |
| API 构建 | `pnpm build` | `tsc` |
| 管理台语法 | `node --check apps/admin/admin.js` | 语法检查 |
| Flutter 稳定版 | `subosito/flutter-action@v2`，开启缓存 | 客户端工具链 |
| 依赖 | `flutter pub get`（`apps/mobile`） | |
| 格式 | `dart format --output=none --set-exit-if-changed lib test` | 格式不符即失败 |
| 分析 | `flutter analyze` | |
| 测试 | `flutter test` | |
| Web 构建 | `flutter build web --release` | 产物 `apps/mobile/build/web` |

### 作业 `android`（Android debug build）

运行环境 `ubuntu-latest`，超时 30 分钟。使用 JDK 17、Flutter stable 和 Gradle 缓存，执行 `flutter build apk --debug`。该作业不使用发布签名，只验证 Android 工程可编译。

## `release.yml`

名称 `Release`。触发条件：

- `push` 标签 `v*`
- `workflow_dispatch`（手动 dry-run，只构建并上传 workflow artifact，不创建 Release）

权限：默认 `contents: read`；Android 发布作业使用 `contents: write` 创建 GitHub Release。

流程：

1. 复用 `ci.yml` 的 `verify` 和 `android` 作业。
2. 校验版本：
   - tag 格式为 `vMAJOR.MINOR.PATCH` 或 `vMAJOR.MINOR.PATCH-<prerelease>`。
   - tag 去掉 `v` 后必须等于 `apps/mobile/pubspec.yaml` 的 SemVer 部分。
   - `pubspec.yaml` 必须包含 `+N` 构建号，作为 Android `versionCode`。
   - tag 提交必须可从 `origin/main` 到达；分支上的 tag 会被拒绝。
3. 从 GitHub Secrets 解码 keystore，生成临时 `apps/mobile/android/key.properties`。
4. 构建：
   - 通用 APK：`flutter build apk --release`
   - 分 ABI APK：`flutter build apk --release --split-per-abi`，覆盖 `arm64-v8a`、`armeabi-v7a`、`x86_64`。
5. 使用 `apksigner` 验证所有 APK 均为 release 签名，拒绝 debug 签名。
6. 生成 `BUILD_INFO.txt` 与 `SHA256SUMS.txt`。
7. 上传 workflow artifact，并在 tag 事件中创建或更新 GitHub Release。
8. 无论成功失败，删除临时 `key.properties` 和 keystore。

发布产物：

- `fstudy-v<version>-universal.apk`
- `fstudy-v<version>-arm64-v8a.apk`
- `fstudy-v<version>-armeabi-v7a.apk`
- `fstudy-v<version>-x86_64.apk`
- `BUILD_INFO.txt`
- `SHA256SUMS.txt`

项目不使用 Google Play，因此不生成 AAB。

### 必需的 GitHub Secrets

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

Secret 值不得写入仓库、日志或文档。缺少任一项时 release workflow 会在构建前失败。

## 不在 CI 中的内容

- 远程数据库迁移（`wrangler d1 migrations apply` 需要账号凭据）。
- 生产部署（需要 Cloudflare 凭据，且生产注册策略需人工确认）。
- 端到端浏览器测试。
- Google Play/AAB 发布。

## 注意事项

- CI 没有配置 `PUB_HOSTED_URL` 等镜像变量；若依赖下载在 CI 中失败，应显式配置，而不是禁用 TLS。
- 新增需要密钥的步骤时，使用 GitHub Secrets 且不得打印其值。
- `AGENT.md` 的“Required Verification”章节与本工作流一致；修改任一方时请同步另一方。
