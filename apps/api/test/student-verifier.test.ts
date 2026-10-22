import { describe, expect, it } from 'vitest';
import { BuptCasStudentVerifier } from '../src/adapters/student-verifier.js';

describe('BUPT CAS student verifier', () => {
  it('no longer exposes a school-password verify path', () => {
    expect(BuptCasStudentVerifier.prototype).not.toHaveProperty('verify');
  });
});

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
// import { afterEach, describe, expect, it, vi } from 'vitest';
// import { BuptCasStudentVerifier } from '../src/adapters/student-verifier.js';

// const casSuccess = `<?xml version="1.0"?>
// <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
  // <cas:authenticationSuccess>
    // <cas:user>20260001</cas:user>
    // <cas:attributes><cas:uid>20260001</cas:uid><cas:name>测试姓名</cas:name></cas:attributes>
  // </cas:authenticationSuccess>
// </cas:serviceResponse>`;

// afterEach(() => vi.unstubAllGlobals());

// describe('BUPT CAS student verifier', () => {
  // it('uses only CAS, validates the ticket and discards real name and CAS attributes', async () => {
    // const calls: Array<{ url: string; init?: RequestInit }> = [];
    // vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      // const url = String(input);
      // calls.push({ url, init });
      // if (init?.method === 'POST') {
        // return new Response('', {
          // status: 302,
          // headers: { location: 'https://ucloud.bupt.edu.cn/?ticket=ST-opaque-ticket' },
        // });
      // }
      // if (url.startsWith('https://auth.bupt.edu.cn/authserver/serviceValidate')) {
        // return new Response(casSuccess, { status: 200 });
      // }
      // return new Response(
        // '<html><input name="execution" value="e1s1"><input name="username"></html>',
        // { status: 200, headers: { 'set-cookie': 'SESSION=opaque; Path=/; Secure' } },
      // );
    // }));

    // const student = await new BuptCasStudentVerifier().verify({
      // studentId: '20260001',
      // password: 'not-logged-or-persisted',
      // claimedDepartmentId: 'computer',
    // });

    // expect(student).toEqual({
      // studentId: '20260001',
      // realName: null,
      // departmentId: 'computer',
    // });
    // expect(calls).toHaveLength(3);
    // expect(calls.every(({ url }) => url.startsWith('https://auth.bupt.edu.cn/'))).toBe(true);
    // expect(calls[0]!.url).toContain('service=https%3A%2F%2Fucloud.bupt.edu.cn');
    // expect(calls[1]!.init?.body).toBeInstanceOf(URLSearchParams);
    // expect((calls[1]!.init?.body as URLSearchParams).get('password')).toBe(
      // 'not-logged-or-persisted',
    // );
    // expect(calls[2]!.url).toContain('ticket=ST-opaque-ticket');
    // expect(calls.some(({ url }) => url.includes('apiucloud.bupt.edu.cn'))).toBe(false);
    // expect(JSON.stringify(student)).not.toContain('测试姓名');
  // });

  // it('fails closed when CAS presents a captcha instead of bypassing it', async () => {
    // vi.stubGlobal('fetch', vi.fn(async () => new Response(
      // '<html><input name="execution" value="e1s1">config.captcha</html>',
      // { status: 200, headers: { 'set-cookie': 'SESSION=opaque; Path=/; Secure' } },
    // )));

    // await expect(new BuptCasStudentVerifier().verify({
      // studentId: '20260001', password: 'secret', claimedDepartmentId: null,
    // })).rejects.toMatchObject({
      // code: 'school_auth_captcha_required',
      // status: 503,
    // });
  // });

  // it('rejects a CAS assertion for a different student identity', async () => {
    // vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      // if (init?.method === 'POST') {
        // return new Response('', {
          // status: 302,
          // headers: { location: 'https://ucloud.bupt.edu.cn/?ticket=ST-ticket' },
        // });
      // }
      // if (String(input).includes('serviceValidate')) {
        // return new Response(casSuccess.replaceAll('20260001', '20260002'), { status: 200 });
      // }
      // return new Response('<input name="execution" value="e1s1">', {
        // status: 200,
        // headers: { 'set-cookie': 'SESSION=opaque; Path=/; Secure' },
      // });
    // }));

    // await expect(new BuptCasStudentVerifier().verify({
      // studentId: '20260001', password: 'secret', claimedDepartmentId: null,
    // })).rejects.toMatchObject({ code: 'school_identity_mismatch', status: 401 });
  // });
// });
