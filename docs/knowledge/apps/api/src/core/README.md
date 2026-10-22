# apps/api/src/core — 共享类型与安全原语

本目录不依赖 HTTP 或具体数据库，被 `modules/`、`adapters/`、`http/` 共同引用。

## 文件

| 文件 | 内容 |
| --- | --- |
| `types.ts` | 数据库抽象、学生验证器接口、运行时依赖注入类型 |
| `errors.ts` | `DomainError`，统一业务错误 |
| `security.ts` | 用户名/历史学号标识哈希、PBKDF2 密码、不透明令牌（CAS 状态加解密已注释） |

## 关键类型（`types.ts`）

```ts
interface SqlDatabase {
  execute<Row>(statement: { sql: string; params?: (string | number | null)[] }): Promise<{ rows: Row[]; changes: number }>;
  batch(statements: SqlStatement[]): Promise<void>; // 原子写入
}

// StudentVerifier / VerifiedStudent：已注释（学生身份验证停用，ADR-021）

type RuntimeDependencies = {
  database: SqlDatabase;
  studentIdPepper: string;
  clock?: () => Date;                       // 测试注入时间
  allowedOrigins?: string[];
  adminBootstrapUsername?, adminBootstrapPassword?;
  casCallbackUrl?, casLoginEnabled?;        // 浏览器 CAS 登录（关闭）
  inviteRegistrationEnabled?: boolean;      // 邀请码注册开关（ADR-021）
};
```

注意：`VerifiedStudent.realName` 类型存在，但实际的验证器返回值会被忽略，真实姓名不落库（见 [ADR-004](../../../../decisions.md#adr-004学号只以-hmac-形式保存不保存真实姓名与学校密码)）。

## `DomainError`

```ts
new DomainError(code: string, message: string, status = 400)
// status ∈ 400 | 401 | 403 | 404 | 409 | 413 | 415 | 429 | 503
```

HTTP 层 `onError` 将其转换为 `{ "error": { "code", "message" } }`，未知异常统一返回 `500 internal_error`，并且只打印错误信息（不打印堆栈中的敏感内容）。

## `security.ts` 导出函数

| 函数 | 说明 |
| --- | --- |
| `hashStudentId(studentId, pepper)` | HMAC-SHA256，返回 64 位十六进制；仅保留给历史 CAS 身份 |
| `hashLoginIdentifier(username)` | SHA-256，返回 64 位十六进制；用于登录节流键，避免保存用户名明文 |
| `createPasswordCredential(password)` | PBKDF2-SHA256，100,000 次，16 字节盐，返回 `{hash, salt, iterations}`（hash/salt 为 base64） |
| `verifyPassword(password, credential)` | 常量时间比较；迭代次数非法或运行时报错时返回 `false`（fail closed） |
| `createOpaqueToken()` | 32 字节随机，base64url，无填充 |
| `hashToken(token)` | SHA-256 十六进制，用于存储令牌 |
| ~~`encryptCasState` / `decryptCasState`~~ | 已注释（验证码状态加密，ADR-007 已替代） |

## 约定

- 所有密码类操作使用 WebCrypto，不依赖 Node 专有模块，保证 Workers 可用。
- PBKDF2 上限 100,000 次由 Workers 运行时限制决定（[ADR-005](../../../../decisions.md#adr-005应用密码使用-pbkdf2-sha256迭代次数-100000)）。
- 新增错误码时，同步在相关测试中断言 `code`，并在 `http/README.md` 错误码表中登记（如有）。
