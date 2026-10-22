import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const source = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', 'apps', 'admin', 'admin.js'),
  'utf8',
);

function loadRequest(fetchImpl) {
  const app = { innerHTML: '', querySelectorAll: () => [] };
  const loginForm = { addEventListener: () => {} };
  const document = {
    querySelector: (selector) => (selector === '#app' ? app : loginForm),
    querySelectorAll: () => [],
  };
  const sandbox = {
    console,
    document,
    fetch: fetchImpl,
    navigator: { clipboard: { writeText: async () => {} } },
    sessionStorage: {
      getItem: () => null,
      removeItem: () => {},
      setItem: () => {},
    },
    setTimeout,
    window: {
      FSTUDY_API_URL: 'https://api.test',
      location: { hostname: 'admin.test', protocol: 'https:' },
    },
  };
  const context = vm.createContext(sandbox);
  vm.runInContext(
    `${source}\n;globalThis.__adminTest = { request };`,
    context,
    { filename: 'admin.js' },
  );
  return context.__adminTest;
}

test('bodyless POST sends a JSON Content-Type', async () => {
  let captured;
  const { request } = loadRequest(async (url, init) => {
    captured = { url, init };
    return { ok: true, status: 201, json: async () => ({ code: 'ABC-123' }) };
  });

  const result = await request('/v1/admin/invites', { method: 'POST' });

  assert.equal(captured.init.method, 'POST');
  assert.equal(captured.init.body, undefined);
  assert.equal(captured.init.headers['content-type'], 'application/json');
  assert.equal(result.code, 'ABC-123');
});

test('bodyless PATCH also sends a JSON Content-Type', async () => {
  let captured;
  const { request } = loadRequest(async (url, init) => {
    captured = { url, init };
    return { ok: true, status: 200, json: async () => ({ ok: true }) };
  });

  await request('/v1/admin/example', { method: 'PATCH' });

  assert.equal(captured.init.headers['content-type'], 'application/json');
});

test('GET does not claim a JSON request body', async () => {
  let captured;
  const { request } = loadRequest(async (url, init) => {
    captured = { url, init };
    return { ok: true, status: 200, json: async () => ({ users: [] }) };
  });

  await request('/v1/admin/users');

  assert.equal(captured.init.headers['content-type'], undefined);
});

test('caller-provided headers still override defaults', async () => {
  let captured;
  const { request } = loadRequest(async (url, init) => {
    captured = { url, init };
    return { ok: true, status: 200, json: async () => ({ ok: true }) };
  });

  await request('/v1/admin/example', {
    method: 'POST',
    headers: { 'content-type': 'application/problem+json' },
  });

  assert.equal(
    captured.init.headers['content-type'],
    'application/problem+json',
  );
});

test('surfaces the API error when JSON Content-Type is rejected', async () => {
  const { request } = loadRequest(async () => ({
    ok: false,
    status: 415,
    json: async () => ({
      error: { code: 'unsupported_media_type', message: '请求必须使用 application/json' },
    }),
  }));

  await assert.rejects(
    () => request('/v1/admin/invites', { method: 'POST' }),
    /application\/json/,
  );
});
