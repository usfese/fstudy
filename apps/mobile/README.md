# FStudy Flutter 客户端

FStudy 的 Flutter 客户端，目标平台为 Web/PWA 与 Android。桌面端以 PWA 形式运行；Android 通过 GitHub Release 直接分发 APK，不使用 Google Play。

## 开发

```bash
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

Android 模拟器默认 API 地址为 `http://10.0.2.2:8787`；真机调试需要可访问的局域网地址或 `adb reverse`。

## 验证与构建

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

Release APK 需要本地 `android/key.properties` 和 keystore；未配置时 Gradle 会直接失败，不会回退到 debug 签名。

## 发布

版本号位于 `pubspec.yaml`，格式为 `MAJOR.MINOR.PATCH+BUILD`。推送 `v*` tag 后，GitHub Actions 会构建通用 APK 与分 ABI APK 并创建 GitHub Release。流程见根目录 [`CONTRIBUTING.md`](../../CONTRIBUTING.md) 和 [`docs/knowledge/apps/mobile/README.md`](../../docs/knowledge/apps/mobile/README.md)。
