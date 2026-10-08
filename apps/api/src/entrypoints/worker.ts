import { D1SqlDatabase } from '../adapters/d1-database.js';
import { DevelopmentStudentVerifier, DisabledStudentVerifier } from '../adapters/student-verifier.js';
import { createApp } from '../http/app.js';
import { AdminService } from '../modules/admin/admin-service.js';

type WorkerEnvironment = {
  DB: D1Database;
  AUTH_MODE: 'dev' | 'disabled';
  STUDENT_ID_PEPPER: string;
  ALLOWED_ORIGINS?: string;
  ADMIN_BOOTSTRAP_USERNAME?: string;
  ADMIN_BOOTSTRAP_PASSWORD?: string;
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
    const dependencies = {
      database: new D1SqlDatabase(environment.DB),
      studentVerifier:
        environment.AUTH_MODE === 'dev'
          ? new DevelopmentStudentVerifier()
          : new DisabledStudentVerifier(),
      studentIdPepper: environment.STUDENT_ID_PEPPER,
      allowedOrigins: (environment.ALLOWED_ORIGINS ?? '')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
      adminBootstrapUsername: environment.ADMIN_BOOTSTRAP_USERNAME,
      adminBootstrapPassword: environment.ADMIN_BOOTSTRAP_PASSWORD,
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
