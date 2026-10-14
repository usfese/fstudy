# apps/admin — 管理控制台（静态前端）

纯 HTML + 原生 JavaScript，没有构建步骤、没有依赖。通过 `fetch` 调用 `/v1/admin/*`。与学生端 Flutter 应用完全分离（不同来源、不同令牌）。

## 文件

| 文件 | 说明 |
| --- | --- |
| `index.html` | 唯一页面，加载 `/style.css` 与 `/admin.js`（模块脚本）|
| `admin.js` | 全部逻辑（约 215 行）：登录、页面路由、渲染、事件 |
| `style.css` | 样式（单行压缩） |

## 运行方式

```bash
python3 -m http.server 8081 --bind 127.0.0.1 --directory apps/admin
# 或
pnpm admin:dev
```

访问 `http://127.0.0.1:8081`。API 默认地址为 `http://<当前主机>:8787`。

部署时，若管理前端与 API 不同源，需在 `index.html` 中、模块脚本之前设置：

```html
<script>window.FSTUDY_API_URL = 'https://api.example.com';</script>
```

并在 API 的 `ALLOWED_ORIGINS` 中加入管理台域名。**当前 `index.html` 没有设置该变量**，仅在本地开发使用默认值。

## 与 API 的交互

| 页面（`pages` 键） | 调用的接口 | 操作 |
| --- | --- | --- |
| `overview` 运营总览 | `GET /v1/admin/overview` | 只读统计 |
| `users` 用户管理 | `GET /v1/admin/users?q=`，`PATCH /v1/admin/users/:id/status` | 搜索、封禁/恢复 |
| `content` 内容管理 | `GET /v1/admin/content`，`PATCH /v1/admin/content/:type/:id` | 隐藏、恢复、删除 |
| `reports` 举报处理 | `GET /v1/admin/reports`，`PATCH /v1/admin/reports/:id` | 解决或驳回 |
| `tags` 标签管理 | `GET /v1/admin/tags`，`POST /v1/admin/tags` | 新增、编辑、启停 |
| `audit` 操作审计 | `GET /v1/admin/audit` | 只读 |
| 登录 | `POST /v1/admin/auth/login` | 获取令牌 |
| 修改密码 | `PUT /v1/admin/auth/password` | 成功后会话被撤销，需重新登录 |
| 退出 | `POST /v1/admin/auth/logout` | 撤销服务端会话 |

## 会话与安全

- 令牌存于 `sessionStorage`（键 `fstudy_admin_token`），关闭标签页即失效；用户名存于 `fstudy_admin_username`。
- `request()` 遇到 401（登录接口除外）即调用 `logoutLocal()` 清理本地状态。
- 所有动态数据经过 `esc()` 转义后再插入 HTML，防止 XSS。新增渲染逻辑时必须沿用该函数。
- 管理员令牌有效期 8 天（服务端决定）。

## 维护注意

- 页面切换通过 `activePage` 与 `renderPage()` 实现，没有路由库；新增页面需同时修改 `pages` 对象与 `renderPage` 的分支。
- CI 只对 `admin.js` 做语法检查（`node --check apps/admin/admin.js`），没有 UI 测试。
- `admin.js` 中大量使用内联 `data-*` 属性传参（如 `data-user`、`data-action`），后端校验是最终防线，前端不做权限判断。
