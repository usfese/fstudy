import { readFileSync } from 'node:fs';
import { serve } from '@hono/node-server';
import { NodeSqliteDatabase } from '../adapters/node-database.js';
import { DevelopmentStudentVerifier, DisabledStudentVerifier } from '../adapters/student-verifier.js';
import { createApp } from '../http/app.js';
import { AdminService } from '../modules/admin/admin-service.js';

const database = new NodeSqliteDatabase(process.env.FSTUDY_DB_PATH ?? './fstudy.sqlite');
const tables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'",
});
if (tables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0001_initial.sql', import.meta.url), 'utf8'));
}
const planTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'plans'",
});
if (planTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0002_plans.sql', import.meta.url), 'utf8'));
}
const friendTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'friend_requests'",
});
if (friendTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0003_friends.sql', import.meta.url), 'utf8'));
}
const availabilityTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'availability_invites'",
});
if (availabilityTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0004_availability.sql', import.meta.url), 'utf8'));
}
const throttleTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'auth_throttles'",
});
if (throttleTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0005_auth_throttles.sql', import.meta.url), 'utf8'));
}
const projectTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'projects'",
});
if (projectTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0006_projects.sql', import.meta.url), 'utf8'));
}
const forumTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'forum_posts'",
});
if (forumTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0007_forum.sql', import.meta.url), 'utf8'));
}
const adminTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'admin_sessions'",
});
if (adminTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0008_admin.sql', import.meta.url), 'utf8'));
}
const academicSettingsTables = await database.execute<{ name: string }>({
  sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'user_academic_settings'",
});
if (academicSettingsTables.rows.length === 0) {
  database.applyMigration(readFileSync(new URL('../../migrations/0009_academic_settings.sql', import.meta.url), 'utf8'));
}

const authMode = process.env.AUTH_MODE ?? 'dev';
const studentIdPepper = process.env.STUDENT_ID_PEPPER ?? 'local-development-only-pepper';
if (process.env.NODE_ENV === 'production' && studentIdPepper.length < 32) {
  throw new Error('STUDENT_ID_PEPPER must be configured with at least 32 characters in production');
}
const dependencies = {
  database,
  studentVerifier: authMode === 'dev' ? new DevelopmentStudentVerifier() : new DisabledStudentVerifier(),
  studentIdPepper,
  allowedOrigins: (process.env.ALLOWED_ORIGINS ?? 'http://127.0.0.1:8080,http://localhost:8080,http://127.0.0.1:8081,http://localhost:8081')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  adminBootstrapUsername: process.env.ADMIN_BOOTSTRAP_USERNAME,
  adminBootstrapPassword: process.env.ADMIN_BOOTSTRAP_PASSWORD,
};
try {
  await new AdminService(dependencies).bootstrap();
} catch (error) {
  database.close();
  throw error;
}
const app = createApp(dependencies);

const port = Number(process.env.PORT ?? 8787);
const server = serve({ fetch: app.fetch, port });
console.log(`FStudy API listening on http://localhost:${port}`);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
