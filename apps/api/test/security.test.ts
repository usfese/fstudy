import { describe, expect, it } from 'vitest';
import { createPasswordCredential, verifyPassword } from '../src/core/security.js';

describe('password credentials', () => {
  it('uses a PBKDF2 iteration count supported by Cloudflare Workers', async () => {
    const password = 'correct-horse-battery';
    const credential = await createPasswordCredential(password);

    expect(credential.iterations).toBe(100_000);
    await expect(verifyPassword(password, credential)).resolves.toBe(true);
    await expect(verifyPassword('wrong-password', credential)).resolves.toBe(false);
  });

  it('fails closed when a stored credential cannot be derived by the runtime', async () => {
    const credential = await createPasswordCredential('correct-horse-battery');
    await expect(verifyPassword('correct-horse-battery', {
      ...credential,
      iterations: 210_000,
    })).resolves.toBe(false);
  });
});
