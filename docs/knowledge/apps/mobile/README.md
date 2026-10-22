# apps/mobile — Flutter 客户端根目录

包名 `fstudy`，Flutter 稳定版，Dart SDK `^3.13.5`。**当前迭代以 Web/PWA 为主要目标**（`AGENT.md`），Android 与 iOS 工程保留但暂不构建或测试。

## 目录结构

```
apps/mobile/
├── lib/                 应用源码 → lib/README.md、features/README.md
├── test/widget_test.dart  33 个组件/行为测试（使用假仓库）
├── web/                 Web 入口与 PWA 资源（手写，需要关注）
├── android/             Android 平台工程（生成 + 少量配置，暂不构建）
├── ios/                 iOS 平台工程（保留结构，不构建）
├── wrangler.jsonc       生产 Web 的 Workers 静态资源配置（SPA 回退）
├── analysis_options.yaml  引入 flutter_lints，排除 build/android/ios/web
├── pubspec.yaml
├── README.md            Flutter 默认模板，内容未更新（见下）
└── build/               构建产物（已忽略）
```

`apps/mobile/README.md` 仍是 Flutter 模板文字，**不反映项目实际状态**。以本文档与根目录 `README.md` 为准；如需更新，应改写该文件。

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
```

API 地址通过编译参数注入：

```bash
flutter run -d web-server --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

默认值：Web 为 `http://127.0.0.1:8787`，Android 模拟器为 `http://10.0.2.2:8787`。

Web 使用 path URL 策略（`usePathUrlStrategy()`），生产静态托管必须把未知路径重写到 `index.html`。生产 Web 使用 Workers 静态资源部署：`wrangler.jsonc` 设置 `assets.directory=./build/web` 与 `not_found_handling=single-page-application`，命令见根 `README.md` 与 `AGENT.md`。早先的 `fstudy-student` Pages 直传在该账号持续卡在 `upsert-hashes`，因此改用 Worker `fstudy-web`。

## 验证门槛

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

CI 中执行的就是上述命令（见 [.github/workflows](../../.github/workflows/README.md)）。Android 相关命令（`flutter build apk`）只在用户明确恢复 Android 工作后才运行。

## 镜像

网络不稳定时可设置（仅开发机，CI 需单独配置）：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

不得为绕过网络问题而禁用 TLS 校验。

## 待确认

1. `apps/mobile/README.md` 为模板内容，需要替换为项目说明或指向根目录文档。
