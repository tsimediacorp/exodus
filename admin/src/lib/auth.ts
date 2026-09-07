import { createHmac, timingSafeEqual } from 'node:crypto';
import { cookies } from 'next/headers';

const COOKIE = 'exodus_admin';
const MAX_AGE_SECONDS = 60 * 60 * 12;

/**
 * A single shared password, and a signed cookie.
 *
 * Deliberately small. This panel exists for a closed beta and comes out at
 * launch; standing up user accounts and roles for it would be more surface
 * than the thing it guards. What it must not be is guessable or forgeable,
 * hence the HMAC and the constant-time compare.
 *
 * It does mean one shared secret among whoever is testing. If more than a
 * couple of people ever need access, this is the piece to replace first.
 */
export function isConfigured(): boolean {
  return Boolean(process.env.ADMIN_PASSWORD && process.env.ADMIN_SECRET);
}

export function checkPassword(candidate: string): boolean {
  const expected = process.env.ADMIN_PASSWORD ?? '';
  if (!expected) return false;
  const a = Buffer.from(candidate);
  const b = Buffer.from(expected);
  // timingSafeEqual throws on a length mismatch, which would itself leak the
  // length, so both sides are hashed to a fixed width first.
  return timingSafeEqual(sha(a), sha(b));
}

export function mintToken(): string {
  const issued = Date.now().toString();
  return `${issued}.${sign(issued)}`;
}

export async function isSignedIn(): Promise<boolean> {
  const jar = await cookies();
  return verifyToken(jar.get(COOKIE)?.value ?? '');
}

export function verifyToken(token: string): boolean {
  const [issued, signature] = token.split('.');
  if (!issued || !signature) return false;
  const age = Date.now() - Number(issued);
  if (!Number.isFinite(age) || age < 0 || age > MAX_AGE_SECONDS * 1000) return false;
  const expected = sign(issued);
  if (expected.length !== signature.length) return false;
  return timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

export const cookieName = COOKIE;
export const cookieMaxAge = MAX_AGE_SECONDS;

function sign(value: string): string {
  return createHmac('sha256', process.env.ADMIN_SECRET ?? '').update(value).digest('hex');
}

function sha(buffer: Buffer): Buffer {
  return createHmac('sha256', 'length-guard').update(buffer).digest();
}
