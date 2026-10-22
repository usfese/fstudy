const API = window.FSTUDY_API_URL || `${window.location.protocol}//${window.location.hostname}:8787`;
const TOKEN_KEY = 'fstudy_admin_token';
const USER_KEY = 'fstudy_admin_username';
const INVITES_KEY = 'fstudy_admin_invites';
const JSON_METHODS = new Set(['POST', 'PUT', 'PATCH']);
const app = document.querySelector('#app');
let token = sessionStorage.getItem(TOKEN_KEY);
let username = sessionStorage.getItem(USER_KEY) || '';
let activePage = 'overview';
let searchTerm = '';
const pages = {
  overview: ['运营总览', '关键运营指标与近期情况'],
  invites: ['邀请码', '生成并复制注册邀请码'],
  users: ['用户管理', '查找用户并管理账号状态'],
  content: ['内容管理', '管理讨论帖、公开回复与组队帖'],
  reports: ['举报处理', '查看并处理用户提交的举报'],
  tags: ['标签管理', '维护发现与推荐使用的受控标签'],
  audit: ['操作审计', '管理员变更记录'],
};

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

async function request(path, options = {}) {
  const method = (options.method || 'GET').toUpperCase();
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      // The API requires JSON Content-Type for every POST/PUT/PATCH, even
      // when the operation has no request body (e.g. generating an invite).
      ...(JSON_METHODS.has(method) ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && path !== '/v1/admin/auth/login') logoutLocal();
    throw new Error(data?.error?.message || '请求失败');
  }
  return data;
}

function logoutLocal() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(USER_KEY);
  token = null;
  username = '';
  renderLogin();
}

function renderLogin(message = '') {
  app.innerHTML = `<div class="login-wrap"><form class="login" id="login-form">
    <div class="brand">FSTUDY · OPERATIONS</div><h1>管理控制台</h1>
    <div class="muted">使用独立管理员账号登录，不接受学生端会话。</div>
    <div class="field"><label for="username">管理员账号</label><input id="username" name="username" autocomplete="username" required minlength="3" maxlength="64" value="${esc(username)}"></div>
    <div class="field"><label for="password">管理员密码</label><input id="password" name="password" type="password" autocomplete="current-password" required></div>
    <div class="error" id="login-error">${esc(message)}</div><button class="button" type="submit">安全登录</button>
    <p class="muted" style="margin:18px 0 0;line-height:1.6">管理员账号由服务端首次启动配置创建；请勿与学生账号共用密码。</p>
  </form></div>`;
  document.querySelector('#login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = event.currentTarget.querySelector('button');
    button.disabled = true;
    document.querySelector('#login-error').textContent = '';
    try {
      const result = await request('/v1/admin/auth/login', {
        method: 'POST',
        body: JSON.stringify({
          username: document.querySelector('#username').value,
          password: document.querySelector('#password').value,
        }),
      });
      token = result.accessToken;
      username = result.username;
      sessionStorage.setItem(TOKEN_KEY, token);
      sessionStorage.setItem(USER_KEY, username);
      await request('/v1/admin/overview');
      activePage = 'overview';
      await renderShell();
    } catch (error) {
      if (token) {
        sessionStorage.removeItem(TOKEN_KEY);
        sessionStorage.removeItem(USER_KEY);
        token = null;
        username = '';
      }
      document.querySelector('#login-error').textContent = error.message;
      button.disabled = false;
    }
  });
}

function renderShell() {
  app.innerHTML = `<div class="shell"><aside class="sidebar"><div class="side-brand">FStudy 管理台<small>OPERATIONS CONSOLE</small></div>
    <nav class="nav">${Object.entries(pages).map(([key, value]) => `<button data-page="${key}" class="${activePage === key ? 'active' : ''}">${value[0]}</button>`).join('')}</nav>
    <div class="side-bottom"><button class="button secondary" id="change-password" style="margin-bottom:8px">修改管理员密码</button><button class="button secondary" id="logout">退出管理员账号</button></div></aside>
    <main class="main"><header class="top"><div><h1 id="page-title"></h1><div class="muted" id="page-caption"></div></div><div class="operator">管理员　<strong>${esc(username)}</strong></div></header>
    <div id="page-content"><div class="loading">加载中…</div></div></main></div>`;
  app.querySelectorAll('[data-page]').forEach((button) => button.addEventListener('click', async () => {
    activePage = button.dataset.page;
    await renderShell();
  }));
  document.querySelector('#logout').addEventListener('click', async () => {
    try { await request('/v1/admin/auth/logout', { method: 'POST' }); } catch (_) { /* local logout still revokes the browser token */ }
    logoutLocal();
  });
  document.querySelector('#change-password').addEventListener('click', async () => {
    const currentPassword = prompt('请输入当前管理员密码');
    if (!currentPassword) return;
    const newPassword = prompt('请输入新密码（至少 14 位）');
    if (!newPassword) return;
    try {
      await request('/v1/admin/auth/password', {
        method: 'PUT', body: JSON.stringify({ currentPassword, newPassword }),
      });
      alert('密码已更新，请使用新密码登录。');
      logoutLocal();
    } catch (error) { alert(error.message); }
  });
  return renderPage();
}

function setPageHeading() {
  document.querySelector('#page-title').textContent = pages[activePage][0];
  document.querySelector('#page-caption').textContent = pages[activePage][1];
}

async function renderPage() {
  setPageHeading();
  const container = document.querySelector('#page-content');
  container.innerHTML = '<div class="loading">加载中…</div>';
  try {
    if (activePage === 'overview') await renderOverview(container);
    if (activePage === 'invites') await renderInvites(container);
    if (activePage === 'users') await renderUsers(container);
    if (activePage === 'content') await renderContent(container);
    if (activePage === 'reports') await renderReports(container);
    if (activePage === 'tags') await renderTags(container);
    if (activePage === 'audit') await renderAudit(container);
  } catch (error) {
    container.innerHTML = `<div class="message">${esc(error.message)}</div><button class="button secondary" id="retry">重试</button>`;
    document.querySelector('#retry').addEventListener('click', renderPage);
  }
}

async function renderOverview(container) {
  const data = await request('/v1/admin/overview');
  const metrics = [
    ['注册用户', data.users], ['近 24 小时新增用户', data.todayUsers], ['讨论帖子', data.posts],
    ['近 24 小时新增讨论', data.todayPosts], ['公开回复', data.replies], ['组队帖', data.projects],
    ['近 24 小时新增组队', data.todayProjects], ['待处理举报', data.openReports], ['正常用户', data.activeUsers], ['启用标签', data.tags],
  ];
  container.innerHTML = `<div class="grid">${metrics.map(([label, value]) => `<article class="stat"><div class="stat-label">${label}</div><div class="stat-value">${Number(value).toLocaleString('zh-CN')}</div></article>`).join('')}</div>
    <section class="panel"><h2>运营控制台已就绪</h2><div class="muted" style="line-height:1.8">管理员登录与学生登录使用独立的会话表；管理写操作会记录审计日志。请通过“举报处理”建立内容反馈闭环，通过“用户管理”执行封禁或恢复。</div></section>`;
}

function loadInviteDrafts() {
  try {
    const value = JSON.parse(sessionStorage.getItem(INVITES_KEY) || '[]');
    return Array.isArray(value)
      ? value.filter((item) => item && typeof item.code === 'string')
      : [];
  } catch (_) {
    return [];
  }
}

function saveInviteDrafts(invites) {
  sessionStorage.setItem(INVITES_KEY, JSON.stringify(invites));
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (_) {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try {
      return document.execCommand('copy');
    } finally {
      area.remove();
    }
  }
}

async function renderInvites(container) {
  const invites = loadInviteDrafts();
  container.innerHTML = `<section class="panel">
    <h2>生成注册邀请码</h2>
    <p class="muted" style="line-height:1.7;margin-top:0">运营邀请码不占用学生个人额度。邀请码只在生成时显示一次，请立即复制；关闭当前标签页后本次列表会清空。</p>
    <div class="toolbar">
      <button class="button" id="generate-invite">生成邀请码</button>
      <button class="button secondary" id="copy-all-invites" ${invites.length ? '' : 'disabled'}>复制全部</button>
      <button class="button secondary" id="clear-invites" ${invites.length ? '' : 'disabled'}>清空本次列表</button>
    </div>
    <div class="error" id="invite-error"></div>
    <div class="invite-list">${invites.length ? invites.map((item, index) => `<div class="invite-line"><code>${esc(item.code)}</code><span class="muted">${esc(item.createdAt || '')}</span><button class="button secondary" data-copy="${index}">复制</button></div>`).join('') : '<div class="empty">还没有生成邀请码</div>'}</div>
  </section>`;

  document.querySelector('#generate-invite').addEventListener('click', async (event) => {
    const button = event.currentTarget;
    button.disabled = true;
    document.querySelector('#invite-error').textContent = '';
    try {
      const result = await request('/v1/admin/invites', { method: 'POST' });
      const next = [...loadInviteDrafts(), {
        code: result.code,
        createdAt: new Date().toLocaleString('zh-CN', { hour12: false }),
      }];
      saveInviteDrafts(next);
      await renderPage();
    } catch (error) {
      const errorBox = document.querySelector('#invite-error');
      if (errorBox) errorBox.textContent = error.message;
      button.disabled = false;
    }
  });

  document.querySelector('#copy-all-invites')?.addEventListener('click', async (event) => {
    const text = invites.map((item) => item.code).join('\n');
    if (!text) return;
    if (await copyText(text)) {
      event.currentTarget.textContent = '已复制';
      setTimeout(() => renderPage(), 900);
    }
  });

  document.querySelector('#clear-invites')?.addEventListener('click', async () => {
    if (!confirm('清空本次生成的邀请码列表？已经复制的邀请码仍然有效。')) return;
    saveInviteDrafts([]);
    await renderPage();
  });

  container.querySelectorAll('[data-copy]').forEach((button) => button.addEventListener('click', async () => {
    const item = invites[Number(button.dataset.copy)];
    if (!item) return;
    if (await copyText(item.code)) {
      button.textContent = '已复制';
      setTimeout(() => { button.textContent = '复制'; }, 1000);
    }
  }));
}

function table(headers, rows, empty = '暂无数据') {
  if (!rows.length) return `<div class="empty">${empty}</div>`;
  return `<div class="table-wrap"><table class="table"><thead><tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;
}

async function renderUsers(container) {
  const data = await request(`/v1/admin/users?q=${encodeURIComponent(searchTerm)}`);
  container.innerHTML = `<section class="panel"><div class="toolbar"><input class="search" id="user-search" placeholder="搜索显示名或用户 ID" value="${esc(searchTerm)}"><button class="button secondary" id="search-users">搜索</button></div>
    ${table(['用户','院系','状态','注册时间','讨论 / 组队','操作'], data.users.map((user) => `<tr><td><strong>${esc(user.displayName)}</strong><div class="muted">${esc(user.id)}</div></td><td>${esc(user.departmentId || '—')}</td><td><span class="badge ${user.status === 'active' ? 'good' : 'warn'}">${user.status === 'active' ? '正常' : '已封禁'}</span></td><td>${esc(user.createdAt?.slice(0,10))}</td><td>${user.postCount} / ${user.projectCount}</td><td><button class="button ${user.status === 'active' ? 'danger' : 'secondary'}" data-user="${esc(user.id)}" data-status="${user.status === 'active' ? 'suspended' : 'active'}">${user.status === 'active' ? '封禁' : '恢复'}</button></td></tr>`))}</section>`;
  document.querySelector('#search-users').addEventListener('click', () => { searchTerm = document.querySelector('#user-search').value; renderPage(); });
  document.querySelector('#user-search').addEventListener('keydown', (event) => { if (event.key === 'Enter') document.querySelector('#search-users').click(); });
  container.querySelectorAll('[data-user]').forEach((button) => button.addEventListener('click', async () => {
    if (!confirm(button.dataset.status === 'suspended' ? '封禁后该用户会立即退出所有会话，确认继续？' : '确认恢复该用户账号？')) return;
    await request(`/v1/admin/users/${encodeURIComponent(button.dataset.user)}/status`, { method:'PATCH', body:JSON.stringify({status:button.dataset.status}) });
    renderPage();
  }));
}

const kindNames = { forum_post:'讨论帖', forum_reply:'公开回复', project:'组队帖', reply:'公开回复', general:'综合', course:'课程', campus:'校园', experience:'经验分享' };
async function renderContent(container) {
  const data = await request('/v1/admin/content');
  container.innerHTML = `<section class="panel">${table(['内容','作者','类型','状态','发布时间','操作'], data.content.map((item) => {
    const type = item.contentType;
    const hidden = item.moderationStatus === 'hidden' || item.moderationStatus === 'closed';
    return `<tr><td><strong>${esc(item.content)}</strong><div class="muted">${esc(item.id)}</div></td><td>${esc(item.authorName)}</td><td>${kindNames[type]}</td><td><span class="badge ${hidden ? 'warn':'good'}">${hidden ? '已隐藏/关闭':'展示中'}</span></td><td>${esc(item.createdAt?.slice(0,10))}</td><td><div class="row-actions"><button class="button secondary" data-content="${esc(item.id)}" data-type="${type}" data-action="${hidden?'restore':'hide'}">${hidden?'恢复':'隐藏/关闭'}</button><button class="button danger" data-content="${esc(item.id)}" data-type="${type}" data-action="delete">删除</button></div></td></tr>`;
  }))}</section>`;
  container.querySelectorAll('[data-content]').forEach((button) => button.addEventListener('click', async () => {
    if (!confirm(button.dataset.action === 'delete' ? '永久删除该内容？此操作不可撤销。' : '确认执行内容管理操作？')) return;
    await request(`/v1/admin/content/${button.dataset.type}/${encodeURIComponent(button.dataset.content)}`, { method:'PATCH', body:JSON.stringify({action:button.dataset.action}) });
    renderPage();
  }));
}

async function renderReports(container) {
  const data = await request('/v1/admin/reports');
  container.innerHTML = `<section class="panel">${table(['举报人','目标内容','举报原因','状态','提交时间','处理'], data.reports.map((report) => `<tr><td>${esc(report.reporterName)}</td><td><span class="badge">${esc(kindNames[report.targetType] || report.targetType)}</span><div class="report-reason">${esc(report.targetContent || '内容已删除')}</div><div class="muted">${esc(report.targetId)}</div></td><td><div class="report-reason">${esc(report.reason)}</div></td><td><span class="badge ${report.status === 'open'?'warn':'good'}">${report.status === 'open'?'待处理':report.status === 'resolved'?'已处理':'已驳回'}</span></td><td>${esc(report.createdAt?.slice(0,16).replace('T',' '))}</td><td>${report.status === 'open' ? `<div class="row-actions"><button class="button" data-report="${esc(report.id)}" data-status="resolved">已处理</button><button class="button secondary" data-report="${esc(report.id)}" data-status="dismissed">驳回</button></div>`:'—'}</td></tr>`), '暂无举报')}</section>`;
  container.querySelectorAll('[data-report]').forEach((button) => button.addEventListener('click', async () => {
    await request(`/v1/admin/reports/${encodeURIComponent(button.dataset.report)}`, { method:'PATCH', body:JSON.stringify({status:button.dataset.status}) });
    renderPage();
  }));
}

async function renderTags(container) {
  const data = await request('/v1/admin/tags');
  container.innerHTML = `<section class="panel"><h2>新增受控标签</h2><form class="tag-form" id="tag-form"><select name="category"><option value="interest">兴趣</option><option value="field">领域</option><option value="goal">目标</option></select><input name="name" placeholder="标签名称" required maxlength="40"><button class="button">添加标签</button></form>
  ${table(['标签名称','分类','状态','操作'], data.tags.map((tag) => `<tr><td><strong>${esc(tag.name)}</strong></td><td>${esc({interest:'兴趣',field:'领域',goal:'目标'}[tag.category])}</td><td><span class="badge ${tag.active?'good':'warn'}">${tag.active?'启用':'已停用'}</span></td><td><button class="button secondary" data-tag="${esc(tag.id)}" data-category="${esc(tag.category)}" data-name="${esc(tag.name)}" data-active="${tag.active ? 'false':'true'}">${tag.active?'停用':'启用'}</button></td></tr>`))}</section>`;
  document.querySelector('#tag-form').addEventListener('submit', async (event) => {
    event.preventDefault(); const form = new FormData(event.currentTarget);
    await request('/v1/admin/tags', {method:'POST',body:JSON.stringify({category:form.get('category'),name:form.get('name'),active:true})}); renderPage();
  });
  container.querySelectorAll('[data-tag]').forEach((button) => button.addEventListener('click', async () => {
    await request('/v1/admin/tags', {method:'POST',body:JSON.stringify({id:button.dataset.tag,category:button.dataset.category,name:button.dataset.name,active:button.dataset.active==='true'})}); renderPage();
  }));
}

async function renderAudit(container) {
  const data = await request('/v1/admin/audit');
  container.innerHTML = `<section class="panel">${table(['时间','管理员','操作','对象类型','对象 ID'], data.entries.map((entry) => `<tr><td>${esc(entry.createdAt?.slice(0,19).replace('T',' '))}</td><td>${esc(entry.actor)}</td><td>${esc(entry.action)}</td><td>${esc(entry.entityType)}</td><td>${esc(entry.entityId)}</td></tr>`), '暂无管理操作')}</section>`;
}

if (token) renderShell().catch(() => logoutLocal());
else renderLogin();
