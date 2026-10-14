# apps/api/src/adapters — 运行时与外部依赖适配器

适配器把“运行环境差异”和“外部系统差异”挡在业务模块之外。业务代码只看到 `core/types.ts` 中的接口。

## 文件

| 文件 | 实现接口 | 运行环境 |
| --- | --- | --- |
| `d1-database.ts` | `SqlDatabase`（`D1SqlDatabase`） | Cloudflare Workers，绑定名 `DB` |
| `node-database.ts` | `SqlDatabase`（`NodeSqliteDatabase`） | 本地 Node 22+，`node:sqlite` |
| `student-verifier.ts` | `StudentVerifier` | 三种实现，按 `AUTH_MODE` 选择 |

## `D1SqlDatabase`

- `execute` → `prepare(sql).bind(...params).all()`，返回 `results` 与 `meta.changes`。
- `batch` → 原生 `client.batch`，多条语句在同一事务中执行。

## `NodeSqliteDatabase`

- 构造时执行 `PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;`。
- `execute`：以 `SELECT|WITH|PRAGMA` 开头的语句走 `.all()`，其余走 `.run()`。这个判断基于正则，**`INSERT ... RETURNING` 之类的语句不会返回行**，目前代码未使用此类语句。
- `batch` → 手动 `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK`。
- 额外方法：`applyMigration(sql)`（`exec`）与 `close()`，只供入口与测试使用。

## `student-verifier.ts`

所有实现都必须满足“不记录学校密码、不保存真实姓名、不请求 UCloud 令牌或角色”。

### `DevelopmentStudentVerifier`（`AUTH_MODE=dev`）

- 学号必须为 8–12 位数字；密码必须等于 `dev-password`，否则 401 `school_auth_failed`。
- 返回固定的 `realName: '开发测试学生'`，但该字段会被忽略。

### `DisabledStudentVerifier`（`AUTH_MODE=disabled`，生产默认）

- 任何调用都抛出 503 `student_verification_unavailable`，“注册已关闭”。

### `BuptCasStudentVerifier`（`AUTH_MODE=bupt-cas`）

常量：

- 登录页：`https://auth.bupt.edu.cn/authserver/login?service=https://ucloud.bupt.edu.cn`
- 校验：`https://auth.bupt.edu.cn/authserver/serviceValidate`
- 超时：10 秒

| 方法 | 作用 |
| --- | --- |
| `authorizationUrl(callbackUrl)` | 构造浏览器跳转 CAS 的地址（`/v1/auth/cas/start` 使用，当前关闭） |
| `verifyTicket(ticket, callbackUrl)` | 调用 `serviceValidate`，解析 XML，学号取 `cas:user`（回退 `uid` / `employeeNumber` 属性），必须为 8–12 位数字；返回 `{ studentId }` |
| `beginPasswordChallenge()` | 访问 CAS 登录页取 `execution` 与 cookie；尝试解析验证码 ID，再拉取验证码图片，返回 `{ state, captchaImage }`（图片为 `data:` URI，≤ 256 KB） |
| `verifyPasswordChallenge({studentId, password, captcha, state})` | 无验证码时直接拒绝（400 `school_auth_captcha_required`）；否则带 cookie、`execution`、验证码 POST 到 CAS 登录页（`redirect: manual`）；302 后取 ticket，以 `ucloud.bupt.edu.cn` 作为 service 调用 `serviceValidate`，并核对学号一致（不一致返回 `school_identity_mismatch`） |
| `verify(input)` | 无验证码的直接密码提交路径（`POST` 登录页）。遇到验证码提示即返回 503，不绕过。由 `POST /v1/auth/register` 经 `AccountService.register` 调用，预发环境该入口默认关闭 |

错误码（CAS 相关）：

| code | HTTP | 含义 |
| --- | --- | --- |
| `school_auth_unavailable` | 503 | CAS 不可达、超时或页面结构异常；**不计入密码失败** |
| `school_auth_captcha_required` | 400 / 503 | 需要验证码 |
| `school_auth_captcha_invalid` | 401 | 验证码错误或过期，可重试（最多 3 次） |
| `school_auth_failed` | 401 | 账号或密码错误，计入失败次数 |
| `school_identity_mismatch` | 401 | CAS 返回的身份与输入学号不一致 |
| `invalid_cas_ticket` / `invalid_cas_identity` | 401 | 票据或学号格式不合法 |

#### 当前状态（重要）

- 验证码图片获取不稳定：预发环境挑战返回有效 `challengeId`，但 `captchaImage: null`。原因是北邮登录页的验证码由混淆后的前端脚本动态初始化（`login-normal.html` → `index-normal` 脚本），当前解析逻辑没有复现该接口。
- 因此 `SCHOOL_PASSWORD_REGISTRATION_ENABLED` 在预发保持 `false`。在 `captchaImage` 能被用户在界面中看到之前，**不要提交任何真实密码**。
- 浏览器跳转式 CAS 因北邮返回“未认证授权的服务”而无法使用，`CAS_LOGIN_ENABLED` 保持 `false`。

## 扩展方式

- 新增学生验证来源：实现 `StudentVerifier`，在两个入口的 `AUTH_MODE` 分支中注册，并补充测试（参照 `test/student-verifier.test.ts`）。
- 新增数据库后端：实现 `SqlDatabase`，保证 `batch` 原子性，不能改变 SQL 语义。
