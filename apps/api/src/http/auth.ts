import type { MiddlewareHandler } from 'hono';
import type { AccountService } from '../modules/identity/account-service.js';

export type AppVariables = { userId: string; accessToken: string };

export function bearerToken(header: string | undefined): string | null {
  if (!header?.startsWith('Bearer ') || header.length > 256) return null;
  const value = header.slice('Bearer '.length).trim();
  return /^[A-Za-z0-9_-]{40,128}$/.test(value) ? value : null;
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
