# FStudy 项目知识库

本目录与代码结构一一对应：每个重要文件夹都有一份 `README.md`，记录该目录的职责、架构、接口定义和重要约束。跨目录的架构决策集中记录在 [decisions.md](./decisions.md)。

> 编写时间：2026-10-14。内容基于当前工作区（包含大量未提交改动，见下文“状态说明”）。代码变化后请同步更新对应目录的文档。

## 项目一句话

面向北京邮电大学学生的课业与轻社交应用：手动课表、作业、自定义安排、好友与共同空闲、组队项目、讨论区，以及管理后台。

## 目录索引

| 路径 | 说明 |
| --- | --- |
| [apps/api](./apps/api/README.md) | Hono API 包根目录：脚本、环境变量、部署配置 |
| [apps/api/src/core](./apps/api/src/core/README.md) | 共享类型、错误、安全原语（哈希、PBKDF2、AES-GCM） |
| [apps/api/src/adapters](./apps/api/src/adapters/README.md) | 运行时与外部依赖适配器：D1、node:sqlite、学生身份验证器 |
| [apps/api/src/entrypoints](./apps/api/src/entrypoints/README.md) | Node 与 Cloudflare Workers 启动入口 |
| [apps/api/src/http](./apps/api/src/http/README.md) | HTTP 路由、中间件、请求校验、**全部接口定义** |
| [apps/api/src/modules](./apps/api/src/modules/README.md) | 业务模块（身份、课表、作业、好友、项目、论坛、管理等）|
| [apps/api/migrations](./apps/api/migrations/README.md) | 数据库迁移与表结构 |
| [apps/api/test](./apps/api/test/README.md) | API 测试套件 |
| [apps/admin](./apps/admin/README.md) | 管理后台静态前端 |
| [apps/mobile](./apps/mobile/README.md) | Flutter 客户端（Web 优先）根目录与构建 |
| [apps/mobile/lib](./apps/mobile/lib/README.md) | Flutter 应用组装、路由、会话、仓库模式 |
| [apps/mobile/lib/features](./apps/mobile/lib/features/README.md) | 各功能模块与其调用的后端接口映射 |
| [.github/workflows](./.github/workflows/README.md) | CI 流水线 |
| [decisions.md](./decisions.md) | 重大架构决策记录（ADR） |

## 整体架构

```
┌──────────────────────┐     ┌──────────────────────┐
│ apps/mobile (Flutter)│     │ apps/admin (静态 JS) │
│ Web/PWA 优先         │     │ 独立管理员会话       │
└──────────┬───────────┘     └──────────┬───────────┘
           │ Bearer token (学生)         │ Bearer token (管理员)
           ▼                            ▼
┌────────────────────────────────────────────────────┐
│ apps/api  (Hono + TypeScript)                       │
│  entrypoints/node.ts     ──┐                        │
│  entrypoints/worker.ts   ──┼─► http/app.ts (路由)   │
│                            │      │                  │
│                            │      ▼                  │
│                            │  modules/* (业务逻辑)   │
│                            │      │                  │
│                            ▼      ▼                  │
│             adapters/ + core/types.ts (SqlDatabase、  │
│             StudentVerifier 抽象)                     │
└──────┬──────────────────────────────────┬──────────┘
       │ node:sqlite (本地 fstudy.sqlite)  │ Cloudflare D1 (生产/预发)
       ▼                                  ▼
  migrations/*.sql（前向迁移，编号 0001–0013）
```

请求链路：`entrypoint` 组装依赖 → `createApp(dependencies)` 注册全局中间件（安全头、CORS、请求体大小、Content-Type）→ 路由层用 Zod 校验请求 → 调用 `modules/*` 服务 → 通过 `SqlDatabase` 访问数据库。统一错误格式为 `{ "error": { "code", "message" } }`，由 `DomainError` 抛出。

## 状态说明（2026-10-14）

- 当前工作区相对最后一次提交（`8fa542a`）约有 30 个文件被修改，另有未跟踪的 `0010`–`0013` 迁移、`modules/notifications/`、`features/notifications/` 与 `test/student-verifier.test.ts`。这些内容在本知识库中按工作区现状描述。
- 身份认证的北邮 CAS 验证码流程**尚未可用**（预发环境 `captchaImage` 为 null，注册开关关闭）。生产环境 `AUTH_MODE=disabled`，注册关闭。详见 [apps/api/src/adapters](./apps/api/src/adapters/README.md)。
- 本地开发学生验证器 `DevelopmentStudentVerifier` 只能在 `AUTH_MODE=dev` 下使用，固定密码 `dev-password`。

## 维护约定

- 新增接口：同步更新 [apps/api/src/http/README.md](./apps/api/src/http/README.md) 的接口表，并在 `app.ts` 的 OpenAPI 文档中补充 summary（`AGENT.md` 要求）。
- 新增迁移：更新 [apps/api/migrations/README.md](./apps/api/migrations/README.md) 的表结构与迁移历史；不要修改已部署的迁移。
- 重大决策（新依赖、安全边界、存储或部署方式变化）：在 [decisions.md](./decisions.md) 追加新条目，不删除旧条目，过时的条目标记为“已替代”。
- 文档语言：中文说明，代码标识符保持英文，与 `AGENT.md` 一致。
