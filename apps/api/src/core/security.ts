const encoder = new TextEncoder();
// Cloudflare Workers WebCrypto currently rejects PBKDF2 iteration counts above 100,000.
const PASSWORD_ITERATIONS = 100_000;
const MAX_SUPPORTED_PASSWORD_ITERATIONS = 100_000;

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function hashLoginIdentifier(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export async function hashStudentId(studentId: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(studentId));
  return bytesToHex(new Uint8Array(signature));
}

async function derivePassword(password: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: salt as BufferSource, iterations },
    key,
    256,
  );
  return bytesToBase64(new Uint8Array(bits));
}

export async function createPasswordCredential(password: string): Promise<{
  hash: string;
  salt: string;
  iterations: number;
}> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return {
    hash: await derivePassword(password, salt, PASSWORD_ITERATIONS),
    salt: bytesToBase64(salt),
    iterations: PASSWORD_ITERATIONS,
  };
}

export async function verifyPassword(
  password: string,
  credential: { hash: string; salt: string; iterations: number },
): Promise<boolean> {
  if (!Number.isInteger(credential.iterations)
    || credential.iterations < 1
    || credential.iterations > MAX_SUPPORTED_PASSWORD_ITERATIONS) {
    return false;
  }
  try {
    const actual = await derivePassword(password, base64ToBytes(credential.salt), credential.iterations);
    if (actual.length !== credential.hash.length) return false;
    let difference = 0;
    for (let index = 0; index < actual.length; index += 1) {
      difference |= actual.charCodeAt(index) ^ credential.hash.charCodeAt(index);
    }
    return difference === 0;
  } catch {
    return false;
  }
}

export function createOpaqueToken(): string {
  return bytesToBase64(crypto.getRandomValues(new Uint8Array(32)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(token));
  return bytesToHex(new Uint8Array(digest));
}

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
// async function casEncryptionKey(secret: string): Promise<CryptoKey> {
  // const digest = await crypto.subtle.digest('SHA-256', encoder.encode(secret));
  // return crypto.subtle.importKey('raw', digest, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
// }

// export async function encryptCasState(plaintext: string, secret: string): Promise<string> {
  // if (secret.length < 32) throw new Error('CAS_STATE_ENCRYPTION_KEY must be at least 32 characters');
  // const iv = crypto.getRandomValues(new Uint8Array(12));
  // const ciphertext = await crypto.subtle.encrypt(
    // { name: 'AES-GCM', iv }, await casEncryptionKey(secret), encoder.encode(plaintext),
  // );
  // const packed = new Uint8Array(iv.length + ciphertext.byteLength);
  // packed.set(iv);
  // packed.set(new Uint8Array(ciphertext), iv.length);
  // return bytesToBase64(packed);
// }

// export async function decryptCasState(encrypted: string, secret: string): Promise<string> {
  // if (secret.length < 32) throw new Error('CAS_STATE_ENCRYPTION_KEY must be at least 32 characters');
  // const packed = base64ToBytes(encrypted);
  // if (packed.length < 13) throw new Error('Invalid encrypted CAS state');
  // const iv = packed.slice(0, 12);
  // const ciphertext = packed.slice(12);
  // const plaintext = await crypto.subtle.decrypt(
    // { name: 'AES-GCM', iv: iv as BufferSource }, await casEncryptionKey(secret), ciphertext as BufferSource,
  // );
  // return new TextDecoder().decode(plaintext);
// }
