# apps/api/test — API 测试套件

使用 Vitest（`pnpm test`）。测试直接调用 `createApp(...)`，数据库为内存中的 `NodeSqliteDatabase(':memory:')`，并在测试中按顺序应用全部迁移，因此测试不依赖本地 `fstudy.sqlite`，也不发起真实网络请求。

## 文件

| 文件 | 测试数 | 内容 |
| --- | --- | --- |
| `app.test.ts` | 28 | 端到端的 HTTP 行为：安全头、请求体限制、注册/登录、CAS 流程、课表、作业、计划、发现、好友、共同空闲（含可见级别）、身份过期与续期、项目、论坛、管理员、举报、标签 |
| `security.test.ts` | 2 | PBKDF2 迭代次数在 Workers 允许范围内；运行时无法派生凭据时 fail closed |
| `student-verifier.test.ts` | 3 | CAS 验证器只使用 CAS，丢弃真实姓名与 CAS 属性；遇到验证码时失败而不绕过；拒绝与输入学号不一致的身份 |

合计 33 个测试。

## 测试夹具（`app.test.ts`）

`testApp({ casLoginEnabled, schoolPasswordRegistrationEnabled, studentVerifier })` 的做法：

1. 创建内存数据库，依次执行 `0001` 至 `0013` 迁移文件（**新增迁移必须同时加入这里**，否则测试与生产结构会不一致）。
2. 构造 `RuntimeDependencies`：`DevelopmentStudentVerifier` 为默认验证器，`studentIdPepper` 为测试用值，`clock` 可注入。
3. 返回 `createApp(dependencies)` 与测试辅助函数。

`latestDatabase` 变量保存最近一次数据库，用于在测试中直接检查表内容。

## 覆盖的重要行为

- **HTTP 边界**：安全头与 CORS 白名单；不支持的 Content-Type 与超大请求体；格式错误的 Bearer 令牌在查库前即被拒绝。
- **身份与会话**：开发学生注册后不保存学校密码；学校验证暂时不可用不计入密码失败；注册入口在浏览器身份认证开启时关闭；CAS 关闭时拒绝跳转登录；验证码挑战只保存加密状态、限制签发频率、一次性消费；CAS 完成流程的 state 绑定与一次性 code；登录失败限流与登出撤销；未注册与密码错误返回相同错误。
- **课表与学习**：手动课程创建与查询；学期起始日必须为周一；计划的创建、提醒与完成。
- **社交**：标签保存与推荐只包含公开、已选择的用户；好友请求不重复；共同空闲计算与空闲邀请处理。
- **组队**：发布标签项目并接受申请；并发接受申请不会超员（见 [ADR-012](../../../decisions.md#adr-012并发安全通过-sql-条件写入保证而不是应用层加锁)）。
- **论坛与治理**：发帖、筛选、公开回复；管理员与学生认证隔离；内容审核与审计；举报受理；封禁用户撤销会话并移出推荐；受控标签的创建与审计。

## 运行与维护

```bash
pnpm --filter @fstudy/api test
```

维护注意：

- 测试名称应描述用户可观察的行为，与 `AGENT.md` 的“在公共接口处验证行为”一致。
- `student-verifier.test.ts` 当前是未提交文件（`??`），需要随本次改动一起纳入版本控制。
- 此前的交接记录提到迁移夹具曾出现 `no such column: student_id_hash` 与重复 `attempt_count` 的错误；当前 `0012`/`0013` 的内容已调整，改动迁移后必须重新运行完整测试。

## 验证命令

```bash
pnpm check   # tsc --noEmit
pnpm test    # vitest run
pnpm build   # tsc 输出 dist/
```
