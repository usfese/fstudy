# apps/api/test — API 测试套件

使用 Vitest（`pnpm test`）。测试直接调用 `createApp(...)`，数据库为内存中的 `NodeSqliteDatabase(':memory:')`，并在测试中按顺序应用全部迁移，因此测试不依赖本地 `fstudy.sqlite`，也不发起真实网络请求。

## 文件

| 文件 | 测试数 | 内容 |
| --- | --- | --- |
| `app.test.ts` | 31 | 端到端的 HTTP 行为：安全头、请求体限制、邀请码注册与邮箱记录、邀请额度与跨月重置、注册冲突、运营邀请码、登录与登出、CAS 浏览器登录（开关关闭与状态绑定）、课表、作业、计划、发现、好友、共同空闲（含可见级别）、身份过期与续期、项目、论坛、管理员、举报、标签 |
| `security.test.ts` | 2 | PBKDF2 迭代次数在 Workers 允许范围内；运行时无法派生凭据时 fail closed |
| `student-verifier.test.ts` | 1 | 占位测试：确认学校密码 `verify` 路径已停用。原有的 CAS 与验证码测试已注释 |

合计 34 个测试。

## 测试夹具（`app.test.ts`）

`testApp({ casLoginEnabled, inviteRegistrationEnabled, clock })` 的做法：

1. 创建内存数据库，依次执行 `0001` 至 `0014` 迁移文件（**新增迁移必须同时加入这里**，否则测试与生产结构会不一致）。
2. 写入 60 个运营邀请码（`TEST-INVITE-000` 至 `059`），保存在 `invitePool` 中，每次测试从中领取。
3. 构造 `RuntimeDependencies`，`studentIdPepper` 为测试用值，`clock` 可注入（用于跨月额度测试）。
4. `register(app, {...})` 辅助函数默认使用 `invitePool` 中的下一个码，邮箱默认为 `<用户名>@example.edu`。

`latestDatabase` 变量保存最近一次数据库，用于在测试中直接检查表内容。

## 覆盖的重要行为

- **HTTP 边界**：安全头与 CORS 白名单；不支持的 Content-Type 与超大请求体；无请求体的 POST 仍必须声明 `application/json`（运营邀请码生成、退出登录）；格式错误的 Bearer 令牌在查库前即被拒绝。
- **身份与会话**：注册需要邀请码，邀请码只能使用一次；邮箱唯一并被记录；注册开关关闭时拒绝注册；用户名或邮箱重复时返回 409；CAS 关闭时拒绝跳转登录；CAS state 绑定；CAS 结果不能创建新账户；登录失败限流与登出撤销；未注册与密码错误返回相同错误。
- **身份期限**：遗留 `student_identities.expires_at` 被设为过去日期后，现有会话、登录和发现仍可正常使用（ADR-022）。
- **课表与学习**：手动课程创建与查询；学期起始日必须为周一；计划的创建、提醒与完成。
- **社交**：用户创建全局标签、同名复用、跨分类隔离、非法分类与未登录拒绝；标签保存与推荐只包含公开、已选择的用户；好友请求不重复；共同空闲计算与空闲邀请处理。
- **组队**：发布标签项目并接受申请；并发接受申请不会超员（见 [ADR-012](../../../decisions.md#adr-012并发安全通过-sql-条件写入保证而不是应用层加锁)）。
- **论坛与治理**：发帖、筛选、公开回复；管理员与学生认证隔离；内容审核与审计；举报受理；封禁用户撤销会话并移出推荐；受控标签的创建与审计。

## 运行与维护

```bash
pnpm --filter @fstudy/api test
```

维护注意：

- 测试名称应描述用户可观察的行为，与 `AGENT.md` 的“在公共接口处验证行为”一致。
- 验证码与学校密码测试已注释（ADR-021）。`student-verifier.test.ts` 保留一个占位测试，防止误启用。
- 此前的交接记录提到迁移夹具曾出现 `no such column: student_id_hash` 与重复 `attempt_count` 的错误；当前 `0012`/`0013` 的内容已调整，改动迁移后必须重新运行完整测试。

## 验证命令

```bash
pnpm check   # tsc --noEmit
pnpm --filter @fstudy/api test    # vitest run
pnpm build   # tsc 输出 dist/
```
