# apps/mobile — Flutter 客户端根目录

包名 `fstudy`，Flutter 稳定版，Dart SDK `^3.13.5`。Web/PWA 与 Android 均为发布目标（`AGENT.md`）；Android Release 由 tag 驱动的 GitHub Actions 构建并直接分发 APK，不使用 Google Play。iOS 工程保留但暂不构建。

## 目录结构

```
apps/mobile/
├── lib/                 应用源码 → lib/README.md、features/README.md
├── test/widget_test.dart  41 个组件/行为测试（使用假仓库）
├── test/class_periods_test.dart  4 个固定节次与短期输入记忆单元测试
├── test/auth_repository_test.dart  6 个会话持久化单元测试（假 Dio 适配器 + 内存存储）
├── web/                 Web 入口与 PWA 资源（手写，需要关注）
├── android/             Android 平台工程（参与 CI 调试构建与 tag 发布）
├── ios/                 iOS 平台工程（保留结构，不构建）
├── wrangler.jsonc       生产 Web 的 Workers 静态资源配置（SPA 回退，`fstudy.usfese.cc`）
├── wrangler.staging.jsonc  预发 Web 的 Workers 静态资源配置（`fstudy-staging.usfese.cc`）
├── analysis_options.yaml  引入 flutter_lints，排除 build/android/ios/web
├── pubspec.yaml
├── README.md            客户端开发、构建与发布入口
└── build/               构建产物（已忽略）
```

`apps/mobile/README.md` 提供客户端开发、构建与发布入口；模块级约束与架构细节以本文档和根目录 `README.md` 为准。

## 依赖（`pubspec.yaml`）

| 依赖 | 版本 | 用途 | 使用状态 |
| --- | --- | --- | --- |
| `flutter_riverpod` | ^3.4.3 | 状态管理依赖 | **保留，预留**（未在 `lib/` 中引用，ADR-020） |
| `go_router` | ^18.0.2 | 顶层路由与浏览器 URL | 使用 |
| `dio` | ^5.11.1 | HTTP 客户端 | 使用（所有 `Dio*Repository`） |
| `flutter_secure_storage` | ^11.2.0 | 保存访问令牌与主题偏好 | 使用 |
| `url_launcher` | ^6.3.2 | 打开外部页面（北邮 CAS 跳转、校园地图外链） | 使用 |
| `drift` / `sqlite3` / `sqlite3_flutter_libs` | ^2.35.1 / **3.5.2（钉死）** / ^0.6.0+eol | 本地数据库 | **保留，预留**（计划中的离线存储，ADR-020） |
| `flutter_local_notifications` | ^22.3.1 | 本地通知 | **保留，预留**，为未来的 Android 版本准备（ADR-020）。Android 通知暂缓（`AGENT.md`） |
| `cupertino_icons` | ^1.0.8 | 图标 | 随模板保留 |

依赖说明：

- `sqlite3` 钉死在 `3.5.2`，原因见 `AGENT.md`「Known Environment Notes」（新版本原生资源下载不稳定）。
- `drift`、`flutter_riverpod`、`flutter_local_notifications` 当前未被引用，按 ADR-020 有意保留。

## 构建与运行

```bash
cd apps/mobile
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
flutter build web --release       # 产物：build/web

flutter build apk --debug         # Android 调试构建
flutter build apk --release       # 通用 Release APK，需要签名配置
flutter build apk --release --split-per-abi  # 分 ABI Release APK
```

API 地址通过编译参数注入：

```bash
flutter run -d web-server --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

默认值：Web 为 `http://127.0.0.1:8787`，Android 模拟器为 `http://10.0.2.2:8787`。

Web 使用 path URL 策略（`usePathUrlStrategy()`），生产静态托管必须把未知路径重写到 `index.html`。生产与预发 Web 均使用 Workers 静态资源部署：`wrangler.jsonc` / `wrangler.staging.jsonc` 设置 `assets.directory`、`not_found_handling=single-page-application` 和 `usfese.cc` 自定义域名，命令见根 `README.md` 与 `AGENT.md`。早先的 `fstudy-student` Pages 直传在该账号持续卡在 `upsert-hashes`，因此不再使用 Pages。

## 验证门槛

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

CI 中执行上述 Web 验证命令，并额外执行 `flutter build apk --debug`（见 [.github/workflows](../../.github/workflows/README.md)）。涉及 Android、插件或签名配置的改动必须本地或 CI 通过 Android 构建。

## Android 发布与签名

- 版本来源：`pubspec.yaml` 的 `version: MAJOR.MINOR.PATCH+BUILD`。`BUILD` 作为 Android `versionCode`，每次发布递增。
- 发布 tag：`vMAJOR.MINOR.PATCH`，必须位于 `main`，且与 `pubspec.yaml` 的 SemVer 一致。
- 发布工作流：`.github/workflows/release.yml`。它复用 CI，构建通用 APK 与 `arm64-v8a`、`armeabi-v7a`、`x86_64` 分 ABI APK，生成 `SHA256SUMS.txt`，然后创建 GitHub Release。
- 项目不使用 Google Play，因此不生成 AAB。
- 签名配置位于 `apps/mobile/android/key.properties`，指向一个 `.jks`。两者都被 Git 忽略。
- GitHub Actions 通过 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS` 注入签名材料。
- 没有 `key.properties` 时，Gradle 的 release 构建会直接失败，禁止回退到 debug 签名发布。
- `apps/mobile/README.md` 是客户端入口文档；发布与签名细节以本节和 `CONTRIBUTING.md` 为准。

## 镜像

网络不稳定时可设置（仅开发机，CI 需单独配置）：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

不得为绕过网络问题而禁用 TLS 校验。
