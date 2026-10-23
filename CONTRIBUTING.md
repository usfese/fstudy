# 贡献指南

本文档说明 FStudy 的分支、提交、验证与发布流程。开始修改前请先阅读 [`AGENT.md`](AGENT.md) 和 [`docs/knowledge/`](docs/knowledge/)。

## 分支与 Pull Request

- `main` 是受保护的发布分支，禁止直接推送。
- 从最新的 `main` 创建短期分支：
  - `feat/...`：新功能
  - `fix/...`：缺陷修复
  - `docs/...`：文档
  - `chore/...`：构建、CI、依赖与维护
- 所有改动通过 Pull Request 合并，使用 squash merge。
- PR 合并前必须通过 GitHub Actions 的 `CI` 检查，包括 API、管理台、Flutter Web 和 Android 调试构建。
- 提交信息建议使用 Conventional Commits，例如 `feat: add calendar export`、`fix: preserve session on reload`。

## 本地验证

按改动范围执行对应检查：

```bash
pnpm check
pnpm test
pnpm build
pnpm knowledge:check
```

Flutter：

```bash
cd apps/mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

涉及 Android 工程、插件或签名配置时，再执行：

```bash
cd apps/mobile
flutter build apk --debug
```

发布签名只在 GitHub Actions 中注入。本地没有 `apps/mobile/android/key.properties` 时，Release 构建会直接失败，不会回退到 debug 签名。

## 版本与发布

FStudy 使用 `vMAJOR.MINOR.PATCH` 形式的 annotated tag，例如 `v1.0.0`。

发布步骤：

1. 从 `main` 创建发布分支。
2. 更新版本号和构建号：
   ```bash
   pnpm release:version 1.1.0
   ```
   该命令会更新 `apps/mobile/pubspec.yaml`，例如 `1.1.0+2`。
3. 更新 `CHANGELOG.md`。
4. 提交 PR，等待 CI 通过并合并到 `main`。
5. 在 `main` 的最新提交上创建 annotated tag：
   ```bash
   git switch main
   git pull --ff-only
   git tag -a v1.1.0 -m "FStudy v1.1.0"
   git push origin v1.1.0
   ```
6. `.github/workflows/release.yml` 会自动构建并发布 GitHub Release。

发布规则：

- tag 去掉前缀 `v` 后必须与 `apps/mobile/pubspec.yaml` 的 SemVer 部分完全一致。
- `pubspec.yaml` 的 `+N` 是 Android `versionCode`，每次发布必须递增。
- release workflow 会校验 tag 对应提交在 `main` 上；不在 `main` 上的 tag 会被拒绝。
- 已发布的 tag 不要删除或重新打；需要修复时发布新版本。
- 预发布 tag 可以使用 `v1.1.0-rc.1`，GitHub Release 会标记为 prerelease。

发布产物：

- `fstudy-v<version>-universal.apk`
- `fstudy-v<version>-arm64-v8a.apk`
- `fstudy-v<version>-armeabi-v7a.apk`
- `fstudy-v<version>-x86_64.apk`
- `BUILD_INFO.txt`
- `SHA256SUMS.txt`

项目当前不通过 Google Play 分发，因此不生成 AAB；Android 用户直接安装 APK。

## Android 签名

签名材料只保存在本地和 GitHub Actions Secrets 中：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

不要提交 `apps/mobile/android/key.properties`、`*.jks` 或 `*.keystore`，也不要在日志、Issue 或聊天中粘贴密钥和密码。密钥丢失后已发布应用将无法继续更新，请保留离线备份。

## 分支与标签保护

仓库管理员应保持以下设置：

- `main`：要求 Pull Request、CI 通过、线性历史，禁止 force push 和删除。
- `v*` 标签：限制删除和非快进更新。

## 文档

修改代码、接口、构建方式或安全边界时，同步更新对应的 `docs/knowledge/` 文档；重大决策写入 [`docs/knowledge/decisions.md`](docs/knowledge/decisions.md)。
