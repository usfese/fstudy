import type { MiddlewareHandler } from 'hono';
import type { AccountService } from '../modules/identity/account-service.js';
import type { AdminService } from '../modules/admin/admin-service.js';

export type AppVariables = {
  userId: string;
  accessToken: string;
  adminUsername: string;
  adminToken: string;
};

export function bearerToken(header: string | undefined): string | null {
  if (!header?.startsWith('Bearer ') || header.length > 256) return null;
  const value = header.slice('Bearer '.length).trim();
  return /^[A-Za-z0-9_-]{40,128}$/.test(value) ? value : null;
}

export function requireAdminAuthentication(adminService: AdminService): MiddlewareHandler<{
  Variables: AppVariables;
}> {
  return async (context, next) => {
    const token = bearerToken(context.req.header('authorization'));
    const username = await adminService.authenticate(token);
    context.set('adminUsername', username);
    context.set('adminToken', token!);
    await next();
  };
}

export function requireAuthentication(accountService: AccountService): MiddlewareHandler<{
  Variables: AppVariables;
}> {
  return async (context, next) => {
    const token = bearerToken(context.req.header('authorization'));
    const userId = await accountService.authenticate(token);
    context.set('userId', userId);
    context.set('accessToken', token!);
    await next();
  };
}
