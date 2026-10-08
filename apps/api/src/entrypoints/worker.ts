import { D1SqlDatabase } from '../adapters/d1-database.js';
import { DevelopmentStudentVerifier, DisabledStudentVerifier } from '../adapters/student-verifier.js';
import { createApp } from '../http/app.js';

type WorkerEnvironment = {
  DB: D1Database;
  AUTH_MODE: 'dev' | 'disabled';
  STUDENT_ID_PEPPER: string;
  ALLOWED_ORIGINS?: string;
};

export default {
  async fetch(request: Request, environment: WorkerEnvironment): Promise<Response> {
    if (!environment.STUDENT_ID_PEPPER || environment.STUDENT_ID_PEPPER.length < 32) {
      return Response.json(
        { error: { code: 'service_misconfigured', message: '服务配置错误' } },
        { status: 503 },
      );
    }
    const app = createApp({
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
    });
    return await app.fetch(request);
  },
};
