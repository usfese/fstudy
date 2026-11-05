# apps/mobile/lib — 应用组装、路由与会话

本目录是 Flutter 应用的全部源码。各功能的细节见 [features/README.md](./features/README.md)。

## 文件

| 文件 | 职责 |
| --- | --- |
| `main.dart` | 入口：`WidgetsFlutterBinding.ensureInitialized()`，`usePathUrlStrategy()`，注入 `DioAuthRepository` 并 `runApp` |
| `app.dart` | **唯一的组装点**：`FStudyApp`（`StatefulWidget`），包含路由表、会话状态、主题、仓库工厂、按账号创建的 `ClientCache` |
| `core/cache/client_cache.dart` | 按账号持久化的 GET 响应缓存，保存在 `flutter_secure_storage` |
| `core/cache/cached_api.dart` | `CachedApi` mixin：stale-while-revalidate 读取、缓存通知、写操作失效 |
| `core/cache/cache_refresh_mixin.dart` | 页面订阅缓存变更并在后台刷新后重载 |
| `navigation/app_shell.dart` | 主导航外壳：窄屏底部 `NavigationBar`，宽屏（≥ 760 px）侧边导航 |
| `features/*` | 按功能划分的页面与仓库 |

## 组装方式（`app.dart`）

`FStudyApp` 的构造参数：

```dart
FStudyApp({
  required AuthRepository repository,            // 认证仓库，必填
  AcademicRepository Function(AuthSession)? academicRepositoryFactory,
  PlanRepository Function(AuthSession)? planRepositoryFactory,
  ProfileRepository Function(AuthSession)? profileRepositoryFactory,
  SocialRepository Function(AuthSession)? socialRepositoryFactory,
  ProjectRepository Function(AuthSession)? projectRepositoryFactory,
  ForumRepository Function(AuthSession)? forumRepositoryFactory,
  NotificationRepository Function(AuthSession)? notificationRepositoryFactory,
})
```

每个工厂都是可选的：生产环境为 `null`，此时 `_setSession` 使用 `Dio*Repository(accessToken: ..., cache: ...)`，并把同一个 `ClientCache` 注入所有仓库；测试注入假仓库，因此 **widget 测试不发起真实网络请求**。

会话切换统一由 `_setSession(AuthSession?)` 完成：会话为空时清空所有仓库和未读数；非空时按账号创建 `ClientCache`、构造仓库并刷新未读通知数。相同令牌只刷新用户快照时不会重建仓库。退出登录时还会调用 `RecentInputs.clear()` 并删除该账号的缓存，避免同一设备上的数据跨账号泄漏。

## 本地缓存与后台刷新

- `ClientCache` 以账号为单位保存原始 GET 响应，键为 `fstudy_cache_v1_<userId>`，值为 `{entries: {"GET <path>?<query>": {at, data}}}`，落在 `flutter_secure_storage`。
- 仓库通过 `CachedApi.cachedGet` 读取：有缓存先返回缓存；条目超过 TTL 时在后台请求云端。云端数据与缓存不同则写入并通知 `cacheChanges`，页面据此重载；相同则不通知。
- 默认 TTL 为 30 秒；标签 5 分钟、共同空闲 2 分钟、通知 10 秒。写操作成功后按路径失效对应缓存（如 `/v1/courses`、`/v1/plans`）。
- 页面使用 `CacheRefreshMixin` 订阅变更；`FutureBuilder` 在 `connectionState != done && !hasData` 时才显示加载圈，旧数据在后台刷新期间保持可见。
- 缓存只用于读取。所有写入仍直接请求云端，失败时不清空缓存；后台刷新失败时静默保留旧数据，保证离线/部署窗口可用。
- 退出登录或后台校验返回 401 时清空缓存；`clear()` 之后的在途写入会被丢弃。

## 启动与会话恢复

1. `initState` 创建 `GoRouter`，订阅 `repository.sessionChanges`，并调用 `_restoreThemeMode()` 与 `_restoreSession()`。
2. `_restoreSession()` 调用 `repository.restoreSession()`：读取 `fstudy_access_token` 与 `fstudy_access_user`。有本地用户快照时立即返回该会话，同时在后台请求 `GET /v1/me` 校验；没有快照时才等待网络。
3. 后台校验成功会刷新用户快照；用户信息变化时通过 `sessionChanges` 推送新会话。明确返回 401 时清除本地令牌并推送 `null`，应用退回登录页。
4. 恢复期间 `_restoring = true`，路由重定向返回 `null`，不跳转；恢复完成后 `_router.refresh()`。
5. 网络错误或 5xx 时保留缓存会话，部署或离线期间不会丢失登录状态。

### 路由重定向规则

```
_restoring                       → 不重定向
未登录 且 不在 /login             → /login
已登录 且 在 /login 且 无 CAS 回调参数 → /
其他                              → 不变
```

CAS 回调参数（`cas_code` / `cas_state`）的路由解析仍然保留，但 `AuthPage` 已停用 CAS 回调处理（ADR-021）。

## 路由表

| 路径 | 页面 | 备注 |
| --- | --- | --- |
| `/login` | `AuthPage` | 登录与邀请码注册（ADR-021） |
| `/notifications` | `NotificationsPage` | 未登录显示提示文字 |
| `/` | `HomePage` | 首页（`StatefulShellRoute` 分支 0） |
| `/schedule` | `CoursesPage` | 课表（分支 1） |
| `/map` | `CampusMapPage` | 校园地图，本地静态数据（分支 2） |
| `/assignments` | `AssignmentsPage` | 作业（分支 3） |
| `/plans` | `PlansPage` | 自定义安排（分支 4） |
| `/discover` | `DiscoverPage` | 发现同学（分支 5） |
| `/discover/friends` | `FriendsPage` | 子路由 |
| `/discover/availability` | `AvailabilityPage` | 子路由 |
| `/community` | `CommunityPage` | 社区，`tab` 查询参数选择页签（分支 6） |
| `/profile` | `ProfilePage` | 我的（分支 7） |
| `/profile/tags` | `TagSettingsPage` | 子路由 |
| `/profile/about` | `AboutPage` | 子路由，项目介绍与 GitHub 仓库链接 |
| `/projects` | 重定向到 `/community?tab=teams` | 旧地址兼容 |

主导航由 `StatefulShellRoute.indexedStack` 承载，共 8 个分支，标签依次为：首页、课表、地图、作业、安排、发现、社区、我的。

`AGENT.md` 中列出的路由只有 `/login`、`/`、`/schedule`、`/assignments`，已经过时，应更新。

## 导航外壳（`app_shell.dart`）

- `AppShell` 接收 `navigationShell`、`unreadCount`、`onOpenNotifications`、`onThemeModeChanged`、`onLogout`。
- 通知铃铛显示未读数，点击进入 `/notifications`。
- 个人设置中可切换浅色/深色主题，偏好保存在 `fstudy_theme_mode`（`flutter_secure_storage`）。
- 切换分支使用 `goBranch`，并在点击当前分支时回到其 `initialLocation`。

## 仓库模式

每个功能目录遵循相同结构：

```dart
abstract interface class XxxRepository { ... }   // UI 只依赖接口
class DioXxxRepository implements XxxRepository {
  DioXxxRepository({required String accessToken, Dio? dio}) ...
}
```

- `Dio` 实例的 `baseUrl` 取自 `API_BASE_URL` 编译参数，否则使用平台默认值。
- 业务仓库统一通过私有的 `_request` / `_get` 方法执行请求，把 API 返回的 `error.message` 转换为异常（认证侧为 `AuthFailure`），UI 直接展示。
- 写入操作成功后，页面需要立即刷新本地状态（`AGENT.md` 要求，并有对应测试）。

## 约定

- 异步回调中禁止在 `setState` 里返回 `Future`（`AGENT.md`）。
- 新增功能时：先在 `features/<name>/` 写接口与 Dio 实现，再在 `app.dart` 中添加工厂参数、会话联动和路由，最后补充 widget 测试。

## 待确认

1. 地图数据为硬编码的 `_places` 列表，若要扩展需要移到数据文件或后端。
