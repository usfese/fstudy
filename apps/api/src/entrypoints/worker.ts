import { D1SqlDatabase } from '../adapters/d1-database.js';
import { BuptCasStudentVerifier, DevelopmentStudentVerifier, DisabledStudentVerifier } from '../adapters/student-verifier.js';
import { createApp } from '../http/app.js';
import { AdminService } from '../modules/admin/admin-service.js';

type WorkerEnvironment = {
  DB: D1Database;
  AUTH_MODE: 'dev' | 'bupt-cas' | 'disabled';
  STUDENT_ID_PEPPER: string;
  ALLOWED_ORIGINS?: string;
  ADMIN_BOOTSTRAP_USERNAME?: string;
  ADMIN_BOOTSTRAP_PASSWORD?: string;
  CAS_CALLBACK_URL?: string;
  CAS_LOGIN_ENABLED?: string;
  SCHOOL_PASSWORD_REGISTRATION_ENABLED?: string;
  CAS_STATE_ENCRYPTION_KEY?: string;
};

let adminBootstrap: Promise<void> | null = null;

export default {
  async fetch(request: Request, environment: WorkerEnvironment): Promise<Response> {
    if (!environment.STUDENT_ID_PEPPER || environment.STUDENT_ID_PEPPER.length < 32) {
      return Response.json(
        { error: { code: 'service_misconfigured', message: '服务配置错误' } },
        { status: 503 },
      );
    }
    if (environment.SCHOOL_PASSWORD_REGISTRATION_ENABLED === 'true'
      && environment.AUTH_MODE === 'bupt-cas'
      && (!environment.CAS_STATE_ENCRYPTION_KEY || environment.CAS_STATE_ENCRYPTION_KEY.length < 32)) {
      return Response.json(
        { error: { code: 'service_misconfigured', message: '验证码会话加密配置错误' } },
        { status: 503 },
      );
    }
    const dependencies = {
      database: new D1SqlDatabase(environment.DB),
      studentVerifier:
        environment.AUTH_MODE === 'dev'
          ? new DevelopmentStudentVerifier()
          : environment.AUTH_MODE === 'bupt-cas'
          ? new BuptCasStudentVerifier()
          : new DisabledStudentVerifier(),
      studentIdPepper: environment.STUDENT_ID_PEPPER,
      allowedOrigins: (environment.ALLOWED_ORIGINS ?? '')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
      adminBootstrapUsername: environment.ADMIN_BOOTSTRAP_USERNAME,
      adminBootstrapPassword: environment.ADMIN_BOOTSTRAP_PASSWORD,
      casCallbackUrl: environment.CAS_CALLBACK_URL,
      casLoginEnabled: environment.CAS_LOGIN_ENABLED === 'true',
      casStateEncryptionKey: environment.CAS_STATE_ENCRYPTION_KEY,
      schoolPasswordRegistrationEnabled:
        environment.AUTH_MODE === 'dev' || environment.SCHOOL_PASSWORD_REGISTRATION_ENABLED === 'true',
    };
    if (environment.ADMIN_BOOTSTRAP_USERNAME || environment.ADMIN_BOOTSTRAP_PASSWORD) {
      try {
        adminBootstrap ??= new AdminService(dependencies).bootstrap();
        await adminBootstrap;
      } catch {
        adminBootstrap = null;
        return Response.json(
          { error: { code: 'service_misconfigured', message: '管理员配置无效' } },
          { status: 503 },
        );
      }
    }
    const app = createApp(dependencies);
    return await app.fetch(request);
  },
};
