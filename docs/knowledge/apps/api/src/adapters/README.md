# apps/api/src/adapters — 运行时与外部依赖适配器

适配器把“运行环境差异”和“外部系统差异”挡在业务模块之外。业务代码只看到 `core/types.ts` 中的接口。

## 文件

| 文件 | 实现接口 | 运行环境 |
| --- | --- | --- |
| `d1-database.ts` | `SqlDatabase`（`D1SqlDatabase`） | Cloudflare Workers，绑定名 `DB` |
| `node-database.ts` | `SqlDatabase`（`NodeSqliteDatabase`） | 本地 Node 22+，`node:sqlite` |
| `student-verifier.ts` | 无（学生验证已停用，只保留 CAS 票据校验） | — |

## `D1SqlDatabase`

- `execute` → `prepare(sql).bind(...params).all()`，返回 `results` 与 `meta.changes`。
- `batch` → 原生 `client.batch`，多条语句在同一事务中执行。

## `NodeSqliteDatabase`

- 构造时执行 `PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;`。
- `execute`：以 `SELECT|WITH|PRAGMA` 开头的语句走 `.all()`，其余走 `.run()`。这个判断基于正则，**`INSERT ... RETURNING` 之类的语句不会返回行**，目前代码未使用此类语句。
- `batch` → 手动 `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK`。
- 额外方法：`applyMigration(sql)`（`exec`）与 `close()`，只供入口与测试使用。

## `student-verifier.ts`（已停用）

2026-10-14 起，注册不再验证学生身份（[ADR-021](../../../../decisions.md#adr-021邀请码注册记录邮箱停用学生身份验证)）。这里的学校验证代码已经停用或注释：

| 类 | 状态 |
| --- | --- |
| `DevelopmentStudentVerifier` | `verify` 已注释。类保留，不再被运行时使用。 |
| `DisabledStudentVerifier` | 保留，不再被运行时使用。 |
| `BuptCasStudentVerifier.verifyTicket(ticket, callbackUrl)` | **仍有效**，供已关闭的浏览器 CAS 登录使用（`CAS_LOGIN_ENABLED`）。 |
| `BuptCasStudentVerifier.authorizationUrl(callbackUrl)` | **仍有效**，同上。 |
| `BuptCasStudentVerifier.verify` | **已注释**：学校密码直接提交。 |
| `beginPasswordChallenge` / `fetchDynamicCaptchaId` / `verifyPasswordChallenge` | **已注释**：验证码流程。 |

不再使用的类型 `StudentVerifier` 和 `VerifiedStudent` 也已注释。

注释代码保留在原文件中，并带有 `[2026-10-14 已停用]` 标记。恢复前需要新的明确批准，并且需要完成安全评审（参见 ADR-006、ADR-007、ADR-021）。

## 扩展方式

- 新增身份来源前，先确认是否与 ADR-021 冲突。当前注册不接入任何学校验证。
- 新增数据库后端：实现 `SqlDatabase`，保证 `batch` 原子性，不能改变 SQL 语义。
