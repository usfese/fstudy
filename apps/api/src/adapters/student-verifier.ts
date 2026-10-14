import { DomainError } from '../core/errors.js';
import type { StudentVerifier } from '../core/types.js';

export class DevelopmentStudentVerifier implements StudentVerifier {
  async verify(input: {
    studentId: string;
    password: string;
    claimedDepartmentId: string | null;
  }) {
    if (!/^\d{8,12}$/.test(input.studentId)) {
      throw new DomainError('invalid_student_id', '开发学号必须为 8–12 位数字');
    }
    if (input.password !== 'dev-password') {
      throw new DomainError('school_auth_failed', '学校身份验证失败', 401);
    }
    return {
      studentId: input.studentId,
      realName: '开发测试学生',
      departmentId: input.claimedDepartmentId,
    };
  }
}

export class DisabledStudentVerifier implements StudentVerifier {
  async verify(): Promise<never> {
    throw new DomainError(
      'student_verification_unavailable',
      '生产学生身份验证尚未配置，注册已关闭',
      503,
    );
  }
}

const CAS_SERVICE = 'https://ucloud.bupt.edu.cn';
const CAS_LOGIN_URL = `https://auth.bupt.edu.cn/authserver/login?service=${encodeURIComponent(CAS_SERVICE)}`;
const CAS_VALIDATE_URL = 'https://auth.bupt.edu.cn/authserver/serviceValidate';
const CAS_TIMEOUT_MS = 10_000;

export type CasPasswordChallengeState = {
  cookie: string;
  execution: string;
  captchaId: string | null;
};

function decodeXml(value: string): string {
  return value.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (entity, code: string) => {
    if (code.startsWith('#x')) return String.fromCodePoint(Number.parseInt(code.slice(2), 16));
    if (code.startsWith('#')) return String.fromCodePoint(Number.parseInt(code.slice(1), 10));
    return ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" } as Record<string, string>)[code.toLowerCase()] ?? entity;
  });
}

function xmlTag(xml: string, tag: string): string | null {
  const match = new RegExp(`<cas:${tag}>([\\s\\S]*?)<\\/cas:${tag}>`).exec(xml);
  return match ? decodeXml(match[1]!.trim()) : null;
}

/** CAS-only verifier: obtains only an identity assertion, never UCloud tokens or roles. */
export class BuptCasStudentVerifier implements StudentVerifier {
  async beginPasswordChallenge(): Promise<{
    state: CasPasswordChallengeState;
    captchaImage: string | null;
  }> {
    try {
      const initial = await fetch(CAS_LOGIN_URL, {
        headers: { accept: 'text/html' },
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (!initial.ok) throw new Error('CAS login page unavailable');
      const html = await initial.text();
      const setCookie = initial.headers.get('set-cookie');
      const executionMatch = /<input\b[^>]*\bname=["']execution["'][^>]*\bvalue=["']([^"']+)["'][^>]*>/i.exec(html)
        ?? /<input\b[^>]*\bvalue=["']([^"']+)["'][^>]*\bname=["']execution["'][^>]*>/i.exec(html);
      if (!setCookie || !executionMatch) throw new Error('CAS login session unavailable');
      let captchaId = /config\.captcha[^\{]*\{[^}]*?id:\s*['"]([^'"]+)['"]/i.exec(html)?.[1]
        ?? /<img\b[^>]*(?:id|src)=["'][^"']*captcha(?:Id=|\/)([^&"']+)/i.exec(html)?.[1]
        ?? null;
      if (!captchaId && /id=["']captcha["']/.test(html)) {
        captchaId = await this.fetchDynamicCaptchaId(setCookie.split(';', 1)[0]!);
      }
      let captchaImage: string | null = null;
      if (captchaId) {
        const captchaUrl = new URL('/authserver/captcha', 'https://auth.bupt.edu.cn');
        captchaUrl.searchParams.set('captchaId', captchaId);
        captchaUrl.searchParams.set('r', crypto.randomUUID().replaceAll('-', '').slice(0, 12));
        const image = await fetch(captchaUrl, {
          headers: { cookie: setCookie.split(';', 1)[0]! },
          signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
        });
        if (!image.ok) throw new Error('CAS captcha image unavailable');
        const bytes = new Uint8Array(await image.arrayBuffer());
        if (bytes.length === 0 || bytes.length > 256 * 1024) throw new Error('CAS captcha image invalid');
        let binary = '';
        for (const byte of bytes) binary += String.fromCharCode(byte);
        const mime = image.headers.get('content-type')?.split(';')[0] ?? 'image/png';
        captchaImage = `data:${mime};base64,${btoa(binary)}`;
      }
      return {
        state: { cookie: setCookie.split(';', 1)[0]!, execution: executionMatch[1]!, captchaId },
        captchaImage,
      };
    } catch {
      throw new DomainError('school_auth_unavailable', '暂时无法连接北邮认证，请稍后重试', 503);
    }
  }

  private async fetchDynamicCaptchaId(cookie: string): Promise<string> {
    const page = await fetch('https://auth.bupt.edu.cn/authserver/cas/login-normal.html', {
      headers: { cookie, accept: 'text/html' },
      signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
    });
    if (!page.ok) throw new DomainError('school_auth_unavailable', '验证码页面暂时不可用', 503);
    const html = await page.text();
    const scripts = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)]
      .map((match) => match[1]!)
      .filter((src) => /index-normal/i.test(src));
    for (const src of scripts.slice(0, 2)) {
      const scriptUrl = new URL(src, 'https://auth.bupt.edu.cn/authserver/cas/login-normal.html');
      if (scriptUrl.hostname !== 'auth.bupt.edu.cn' || scriptUrl.protocol !== 'https:') continue;
      const response = await fetch(scriptUrl, {
        headers: { cookie, accept: 'application/javascript' },
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (!response.ok) continue;
      const script = await response.text();
      const captcha = /(?:config\.captcha|captcha)\s*=\s*\{[^}]{0,1000}?id\s*:\s*["']([^"']+)["']/is.exec(script)
        ?? /captchaId\s*[=:]\s*["']([^"']+)["']/i.exec(script);
      if (captcha?.[1]) return captcha[1];
    }
    throw new DomainError('school_auth_unavailable', '无法读取北邮验证码会话', 503);
  }

  async verifyPasswordChallenge(input: {
    studentId: string;
    password: string;
    captcha: string | null;
    state: CasPasswordChallengeState;
  }): Promise<{ studentId: string }> {
    if (!/^\d{8,12}$/.test(input.studentId)) {
      throw new DomainError('invalid_student_id', '学号格式无效');
    }
    if (input.state.captchaId && !input.captcha?.trim()) {
      throw new DomainError('school_auth_captcha_required', '请填写北邮页面显示的验证码', 400);
    }
    try {
      const body = new URLSearchParams({
        username: input.studentId,
        password: input.password,
        submit: '登录',
        type: 'username_password',
        execution: input.state.execution,
        _eventId: 'submit',
      });
      if (input.captcha?.trim()) body.set('captcha', input.captcha.trim());
      const response = await fetch(CAS_LOGIN_URL, {
        method: 'POST',
        redirect: 'manual',
        headers: {
          accept: 'text/html',
          'content-type': 'application/x-www-form-urlencoded',
          cookie: input.state.cookie,
          referer: CAS_LOGIN_URL,
        },
        body,
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (response.status !== 302) {
        const html = await response.text();
        if (/captcha|验证码/i.test(html)) {
          throw new DomainError('school_auth_captcha_invalid', '验证码无效或已过期，请重新获取验证码', 401);
        }
        if (response.status === 401 || /用户名或密码|Invalid credentials/i.test(html)) {
          throw new DomainError('school_auth_failed', '北邮账号或密码错误', 401);
        }
        throw new Error('CAS did not return a ticket redirect');
      }
      const location = response.headers.get('location');
      if (!location) throw new Error('CAS ticket redirect missing');
      const redirectUrl = new URL(location, CAS_SERVICE);
      if (redirectUrl.protocol !== 'https:' || redirectUrl.hostname !== new URL(CAS_SERVICE).hostname) {
        throw new Error('Unexpected CAS service redirect');
      }
      const ticket = redirectUrl.searchParams.get('ticket');
      if (!ticket || ticket.length > 4096) throw new Error('CAS ticket missing');
      const verified = await this.verifyTicket(ticket, CAS_SERVICE);
      if (verified.studentId !== input.studentId) {
        throw new DomainError('school_identity_mismatch', '认证返回身份与学号不一致', 401);
      }
      return verified;
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('school_auth_unavailable', '北邮认证暂时不可用，请稍后重试', 503);
    }
  }

  async authorizationUrl(callbackUrl: string): Promise<string> {
    const url = new URL('https://auth.bupt.edu.cn/authserver/login');
    url.searchParams.set('service', callbackUrl);
    return url.toString();
  }

  async verifyTicket(ticket: string, callbackUrl: string): Promise<{ studentId: string }> {
    if (!ticket || ticket.length > 4096) {
      throw new DomainError('invalid_cas_ticket', '认证票据无效', 401);
    }
    try {
      const validateUrl = new URL('https://auth.bupt.edu.cn/authserver/serviceValidate');
      validateUrl.searchParams.set('service', callbackUrl);
      validateUrl.searchParams.set('ticket', ticket);
      const response = await fetch(validateUrl, {
        headers: { accept: 'application/xml, text/xml' },
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (!response.ok) throw new Error('CAS ticket validation unavailable');
      const xml = await response.text();
      if (xml.length > 128 * 1024 || /<!DOCTYPE|<!ENTITY/i.test(xml)) {
        throw new Error('Invalid CAS validation response');
      }
      if (/<cas:authenticationFailure\b/.test(xml)) {
        throw new DomainError('school_auth_failed', '北邮身份认证未通过', 401);
      }
      if (!/<cas:authenticationSuccess>/.test(xml)) throw new Error('CAS validation response malformed');
      const attributeBlock = /<cas:attributes>([\s\S]*?)<\/cas:attributes>/.exec(xml)?.[1] ?? '';
      const studentId = xmlTag(xml, 'user')
        ?? xmlTag(attributeBlock, 'uid')
        ?? xmlTag(attributeBlock, 'employeeNumber');
      if (!studentId || !/^\d{8,12}$/.test(studentId)) {
        throw new DomainError('invalid_cas_identity', '认证结果不是有效的北邮学号', 401);
      }
      return { studentId };
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('school_auth_unavailable', '北邮认证暂时不可用，请稍后重试', 503);
    }
  }

  async verify(input: {
    studentId: string;
    password: string;
    claimedDepartmentId: string | null;
  }) {
    if (!/^\d{8,12}$/.test(input.studentId)) {
      throw new DomainError('invalid_student_id', '学号格式无效');
    }

    let cookie: string;
    let execution: string;
    try {
      const initial = await fetch(CAS_LOGIN_URL, {
        headers: { accept: 'text/html' },
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (!initial.ok) throw new Error('CAS login page unavailable');
      const html = await initial.text();
      const setCookie = initial.headers.get('set-cookie');
      const executionMatch = /<input\b[^>]*\bname=["']execution["'][^>]*\bvalue=["']([^"']+)["'][^>]*>/i.exec(html)
        ?? /<input\b[^>]*\bvalue=["']([^"']+)["'][^>]*\bname=["']execution["'][^>]*>/i.exec(html);
      if (!setCookie || !executionMatch) throw new Error('CAS login session unavailable');
      if (/config\.captcha|name=["']captcha["']/i.test(html)) {
        throw new DomainError('school_auth_captcha_required', '学校认证要求验证码，当前无法安全完成验证', 503);
      }
      cookie = setCookie.split(';', 1)[0]!;
      execution = executionMatch[1]!;
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('school_auth_unavailable', '学校认证暂时不可用，请稍后重试', 503);
    }

    let ticket: string;
    try {
      const body = new URLSearchParams({
        username: input.studentId,
        password: input.password,
        submit: '登录',
        type: 'username_password',
        execution,
        _eventId: 'submit',
      });
      const response = await fetch(CAS_LOGIN_URL, {
        method: 'POST',
        redirect: 'manual',
        headers: {
          accept: 'text/html',
          'content-type': 'application/x-www-form-urlencoded',
          cookie,
          referer: CAS_LOGIN_URL,
        },
        body,
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (response.status === 401) {
        throw new DomainError('school_auth_failed', '学校账号或密码错误', 401);
      }
      if (response.status !== 302) {
        const html = await response.text();
        if (/captcha|验证码/i.test(html)) {
          throw new DomainError('school_auth_captcha_required', '学校认证要求验证码，当前无法安全完成验证', 503);
        }
        throw new Error('CAS authentication did not return a ticket redirect');
      }
      const location = response.headers.get('location');
      if (!location) throw new Error('CAS ticket redirect missing');
      const redirectUrl = new URL(location, CAS_SERVICE);
      if (redirectUrl.hostname !== 'ucloud.bupt.edu.cn' || redirectUrl.protocol !== 'https:') {
        throw new Error('Unexpected CAS service redirect');
      }
      ticket = redirectUrl.searchParams.get('ticket') ?? '';
      if (!ticket || ticket.length > 4096) throw new Error('CAS ticket missing');
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('school_auth_unavailable', '学校认证暂时不可用，请稍后重试', 503);
    }

    try {
      const validateUrl = new URL(CAS_VALIDATE_URL);
      validateUrl.searchParams.set('service', CAS_SERVICE);
      validateUrl.searchParams.set('ticket', ticket);
      const response = await fetch(validateUrl, {
        headers: { accept: 'application/xml, text/xml' },
        signal: AbortSignal.timeout(CAS_TIMEOUT_MS),
      });
      if (!response.ok) throw new Error('CAS ticket validation unavailable');
      const xml = await response.text();
      if (xml.length > 128 * 1024 || /<!DOCTYPE|<!ENTITY/i.test(xml)) {
        throw new Error('Invalid CAS validation response');
      }
      if (/<cas:authenticationFailure\b/.test(xml)) {
        throw new DomainError('school_auth_failed', '学校账号认证未通过', 401);
      }
      if (!/<cas:authenticationSuccess>/.test(xml)) throw new Error('CAS validation response malformed');
      const attributeBlock = /<cas:attributes>([\s\S]*?)<\/cas:attributes>/.exec(xml)?.[1] ?? '';
      const studentId = xmlTag(xml, 'user')
        ?? xmlTag(attributeBlock, 'uid')
        ?? xmlTag(attributeBlock, 'employeeNumber');
      if (studentId !== input.studentId) {
        throw new DomainError('school_identity_mismatch', '学校认证返回的身份与输入学号不一致', 401);
      }
      return {
        studentId,
        // Real names are deliberately not retained by FStudy.
        realName: null,
        departmentId: input.claimedDepartmentId,
      };
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError('school_auth_unavailable', '学校认证暂时不可用，请稍后重试', 503);
    }
  }
}
