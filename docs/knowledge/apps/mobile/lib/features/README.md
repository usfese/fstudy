# apps/mobile/lib/features — 功能模块与接口映射

每个子目录对应一个功能域，通常包含 `*_repository.dart`（抽象接口 + Dio 实现）和一个或多个页面文件。下表列出页面、仓库及其调用的后端接口。

> 接口路径以 [apps/api/src/http/README.md](../../../api/src/http/README.md) 为准。仓库方法名以源码为准。

## 功能总览

| 目录 | 页面 | 仓库 | 调用的接口 |
| --- | --- | --- | --- |
| `auth/` | `auth_page.dart`（`AuthPage`） | `auth_repository.dart`（`AuthRepository` / `DioAuthRepository`） | 认证相关，见下 |
| `home/` | `home_page.dart`（`HomePage`） | 无 | 无，提供课表与作业入口卡片 |
| `academic/` | `courses_page.dart`、`assignments_page.dart` | `academic_repository.dart` | `/v1/me/academic-settings`、`/v1/courses`、`/v1/assignments` |
| `plans/` | `plans_page.dart` | `plan_repository.dart` | `/v1/plans` |
| `profile/` | `profile_page.dart` | `profile_repository.dart` | `/v1/me` |
| `social/` | `discover_page.dart`、`friends_page.dart`、`availability_page.dart`、`tag_settings_page.dart` | `social_repository.dart` | `/v1/tags`、`/v1/me/tags`、`/v1/discover`、`/v1/friend-requests`、`/v1/friends`、`/v1/availability`、`/v1/availability-invites` |
| `projects/` | `projects_page.dart` | `project_repository.dart` | `/v1/tags`、`/v1/projects`、`/v1/project-applications`、`/v1/reports` |
| `community/` | `community_page.dart`（含 `ForumPage` 与各对话框） | `forum_repository.dart` | `/v1/forum/posts`、`/v1/forum/posts/:id`、`/v1/forum/posts/:id/replies`、`/v1/reports` |
| `notifications/` | `notifications_page.dart` | `notification_repository.dart` | `/v1/notifications`、`/v1/notifications/read` |
| `map/` | `campus_map_page.dart` | 无（本地数据） | 无，用 `url_launcher` 打开外部链接 |

---

## auth

### 页面
`AuthPage(repository, onAuthenticated, casCode?, casState?)`：登录与注册。注册需要用户名（3–20 位字母、数字或下划线）、邮箱、邀请码和本系统密码；显示名称默认等于用户名，可在个人资料中修改。学校密码与验证码输入框、北邮跳转登录按钮和 CAS 回调处理已注释停用（ADR-021、ADR-023）。`casCode` / `casState` 参数保留但不再使用。

### 仓库接口（`AuthRepository`）

| 方法 | 接口 | 说明 |
| --- | --- | --- |
| `restoreSession()` | `GET /v1/me`（带令牌） | 读取 `fstudy_access_token`；失败则删除本地令牌并返回 `null` |
| `login({username, appPassword})` | `POST /v1/auth/login` | 成功后保存令牌；用户名不区分大小写 |
| `register({username, email, appPassword, departmentId, inviteCode})` | `POST /v1/auth/register` | 邀请码注册；用户名或邮箱重复 409，邀请码无效 403，注册关闭 403 |
| `startBrowserCas()` | `POST /v1/auth/cas/start` | 取得 `authorizationUrl` 并跳转；当前关闭 |
| `completeBrowserCas({code, state, ...})` | `POST /v1/auth/cas/complete` | 处理回调 code；首次注册需要显示名与本系统密码 |
| ~~`beginCasPasswordChallenge` / `refreshCasPasswordChallenge` / `verifyCasPasswordChallenge`~~ | ~~`/v1/auth/cas/password/*`~~ | 已注释停用（验证码流程） |
| `logout()` | `POST /v1/auth/logout` | 即使服务端失败也会完成本地登出 |

`AuthSession` 包含 `accessToken` 与 `AuthUser`（`id`、`displayName`、`departmentId`）。`AuthFailure` 携带 `message` 与可选 `code`。`CasPasswordChallenge` 类已注释。

API 地址：`String.fromEnvironment('API_BASE_URL')`，默认 Web `http://127.0.0.1:8787`。

---

## academic（课表与作业）

### 页面
- `CoursesPage`：周视图（`_WeeklySchedule`）、课程列表（`_CourseList`）、学期设置（`_SemesterSettings`，选择第一周起始日期，须为周一）、课程对话框（`_CourseDialog`，支持多个上课时间段、单双周）。
- `AssignmentsPage`：作业列表与新增对话框（`_AssignmentDialog`），可关联课程，可切换完成状态。

### 仓库（`AcademicRepository`）

| 方法 | 接口 |
| --- | --- |
| `getSemesterStartDate()` / `setSemesterStartDate(date)` | `GET`/`PUT /v1/me/academic-settings` |
| `listCourses()` / `createCourse(...)` | `GET`/`POST /v1/courses` |
| `listAssignments()` / `createAssignment(...)` | `GET`/`POST /v1/assignments` |
| `setAssignmentCompleted(id, completed)` | `PATCH /v1/assignments/:id/completion` |

---

## plans（自定义安排）

- `PlansPage`：列表与新增（`_PlanDialog`），支持提醒分钟数（可空）。
- `PlanRepository`：`listPlans()`、`createPlan(...)`、`setPlanCompleted(id, completed)`，对应 `/v1/plans` 与 `/v1/plans/:id/completion`。

客户端目前只保存提醒设置，系统通知推送尚未实现（`AGENT.md` 规定 Android 通知暂缓）。

---

## profile（我的）

- `ProfilePage`：显示与编辑资料、隐私设置（`discoverable`、`scheduleVisibility`）、深色模式（通过 `AppShell` 的 `onThemeModeChanged`）、退出登录。
- `ProfileRepository`：`getProfile()`（`GET /v1/me`）、`updateProfile(profile)`（`PATCH /v1/me`）、`getInvites()`（`GET /v1/me/invites`）、`createInvite()`（`POST /v1/me/invites`）。
- 页面底部的“邀请同学”卡片（`_InviteCard`，key `inviteCard`）显示本月剩余额度，按钮 `createInviteButton` 生成邀请码并在对话框中显示一次（`issuedInviteCode`）。额度用完或未加载完成时按钮禁用。

---

## social（发现与好友）

### 页面
- `DiscoverPage`：推荐同学卡片（`_UserCard`），展示共同标签与院系，提供按关系状态变化的操作按钮（`_RelationshipAction`）。
- `FriendsPage`：好友列表，以及收到和发出的请求。
- `AvailabilityPage`：选择好友、日期与周次查询共同空闲段，发起空闲邀请，处理收到的邀请。
- `TagSettingsPage`：按兴趣、方向、目标选择标签，并设置是否核心、是否可见、是否参与推荐。

### 仓库（`SocialRepository`）

| 方法 | 接口 |
| --- | --- |
| `listAvailableTags()` | `GET /v1/tags` |
| `listMyTags()` / `replaceMyTags(tags)` | `GET`/`PUT /v1/me/tags` |
| `discoverUsers()` | `GET /v1/discover` |
| `sendFriendRequest(targetUserId)` | `POST /v1/friend-requests` |
| `listFriends()` | `GET /v1/friends` |
| `respondToFriendRequest(requestId, action)` | `PATCH /v1/friend-requests/:id` |
| `queryAvailability(...)` | `GET /v1/availability` |
| `listAvailabilityInvites()` / `createAvailabilityInvite(...)` | `GET`/`POST /v1/availability-invites` |
| `respondToAvailabilityInvite(inviteId, action)` | `PATCH /v1/availability-invites/:id` |

---

## projects（组队）

- `ProjectsPage`：项目列表（可按标签与状态筛选）、发布项目（`_ProjectDialog`）、申请加入、作者处理申请、举报项目（`_ProjectReportDialog`）。
- `ProjectRepository`：

| 方法 | 接口 |
| --- | --- |
| `listTags()` | `GET /v1/tags` |
| `listProjects({status, tagId})` | `GET /v1/projects` |
| `createProject(...)` | `POST /v1/projects` |
| `setProjectStatus(id, status)` | `PATCH /v1/projects/:id/status` |
| `apply(projectId, message)` | `POST /v1/projects/:id/applications` |
| `listApplications()` / `respond(applicationId, action)` | `GET /v1/project-applications`、`PATCH /v1/project-applications/:id` |
| `reportProject(projectId, reason)` | `POST /v1/reports`（`targetType: project`） |

`ProjectsPage` 嵌在 `CommunityPage` 的“组队”页签中。`app.dart` 中 `/community?tab=teams` 对应 `initialTab = 1`；旧路由 `/projects` 重定向到这里。

---

## community（讨论区）

- `CommunityPage`：`DefaultTabController` 下的两个页签（讨论、组队）。
- `ForumPage`：按分类筛选（`general` / `course` / `campus` / `experience`）、发帖（`_PostDialog`）、帖子与回复（`_ThreadDialog`）、举报（`_ReportDialog`）。
- `ForumRepository`：

| 方法 | 接口 |
| --- | --- |
| `listPosts({category})` | `GET /v1/forum/posts` |
| `createPost(...)` | `POST /v1/forum/posts` |
| `getThread(postId)` | `GET /v1/forum/posts/:id` |
| `createReply(postId, body)` | `POST /v1/forum/posts/:id/replies` |
| `reportContent(...)` | `POST /v1/reports`（`forum_post` 或 `forum_reply`） |

---

## notifications（站内通知）

- `NotificationsPage`：通知列表，点击后标记已读。通过回调 `onUnreadCountChanged` 更新 `AppShell` 的未读数。
- `NotificationRepository`：`list()`（`GET /v1/notifications`，返回 `unreadCount` 与列表），`markRead({id})`（`POST /v1/notifications/read`，省略 `id` 则全部已读）。
- 应用中没有定时轮询（代码中无 `Timer` 或 `Stream.periodic`）。未读数在登录时和打开通知页时刷新。

---

## map（校园地图）

- `CampusMapPage`：按校区分组（`_Campus`）的硬编码地点列表（`_places`），支持搜索，使用 `url_launcher` 打开外部地图。
- 不调用后端。

---

## 测试覆盖

`apps/mobile/test/widget_test.dart` 包含 32 个测试，使用假仓库，不发起真实网络请求。测试名称覆盖了以下流程：

- 未登录时显示登录页，退出登录后返回登录页
- 深色模式设置、通知铃铛打开收件箱并标记已读
- 课程、作业、安排的创建后即时显示，作业完成状态即时更新
- 课表周视图按单双周过滤、设置学期起始日
- 资料与隐私设置保存、标签保存
- 发现页展示、发送并接受好友请求、共同空闲查询与邀请接受
- 项目发布、申请、项目负责人接受申请
- 论坛发帖、公开回复、举报帖子
- 注册时填写邮箱与邀请码并提交（`registration asks for an email and an invite code`）
- 个人页生成邀请码并显示剩余额度（`profile can generate an invite code and shows the remaining quota`）

## 待确认

1. `home_page.dart` 目前只有到课表和作业的入口，首页信息架构由产品决定。
2. 测试名称未显示 CAS 回调处理与各仓库的 HTTP 错误映射，是否需要补充测试由团队决定。
3. 共同空闲页面尚未展示 `friendBlocks`（ADR-019）。后端字段已就绪，展示方式由产品决定。
