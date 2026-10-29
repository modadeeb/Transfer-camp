import { getCookie, setCookie, deleteCookie } from 'hono/cookie';
import { sign, verify } from 'hono/jwt';
import { first } from './db.js';
import { HttpError, forbidden } from './http.js';

export const COOKIE = 'camp_session';
const ITERATIONS = 100000; // Workers' PBKDF2 maximum
const enc = new TextEncoder();

const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(s), (ch) => ch.charCodeAt(0));

async function derive(password, salt, iterations) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  return crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256);
}

export async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const bits = await derive(password, salt, ITERATIONS);
  return `pbkdf2$${ITERATIONS}$${b64(salt)}$${b64(bits)}`;
}

export async function verifyPassword(password, stored) {
  const parts = String(stored || '').split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') return false;
  const bits = new Uint8Array(await derive(password, unb64(parts[2]), Number(parts[1])));
  const expected = unb64(parts[3]);
  if (bits.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < bits.length; i += 1) diff |= bits[i] ^ expected[i];
  return diff === 0;
}

/** Readable temporary password, e.g. "camp-7k3m-9q2x". */
export function tempPassword() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const chars = [...bytes].map((b) => alphabet[b % alphabet.length]);
  return `camp-${chars.slice(0, 4).join('')}-${chars.slice(4).join('')}`;
}

function secret(env) {
  if (!env.JWT_SECRET || env.JWT_SECRET.length < 32) {
    throw new HttpError(500, 'إعداد الخادم ناقص: JWT_SECRET غير مضبوط');
  }
  return env.JWT_SECRET;
}

export async function startSession(c, user, remember) {
  const maxAge = remember ? 60 * 60 * 24 * 30 : 60 * 60 * 12;
  const token = await sign(
    { sub: user.id, sv: user.session_version, exp: Math.floor(Date.now() / 1000) + maxAge },
    secret(c.env),
    'HS256',
  );
  setCookie(c, COOKIE, token, {
    httpOnly: true,
    secure: new URL(c.req.url).protocol === 'https:',
    sameSite: 'Lax',
    path: '/',
    ...(remember ? { maxAge } : {}),
  });
  return token;
}

export function endSession(c) {
  deleteCookie(c, COOKIE, { path: '/' });
}

async function userFromRequest(c) {
  let token = getCookie(c, COOKIE);
  const header = c.req.header('Authorization');
  if (!token && header?.startsWith('Bearer ')) token = header.slice(7);
  if (!token) return null;
  let payload;
  try {
    payload = await verify(token, secret(c.env), 'HS256');
  } catch (e) {
    if (e instanceof HttpError) throw e;
    return null;
  }
  const user = await first(
    c.env.DB,
    'SELECT * FROM users WHERE id = ? AND deleted_at IS NULL AND archived_at IS NULL',
    payload.sub,
  );
  if (!user || user.session_version !== payload.sv) return null;
  return user;
}

/** Requests that change data must carry X-Requested-With (CSRF guard for the cookie session). */
export const csrf = async (c, next) => {
  if (!['GET', 'HEAD', 'OPTIONS'].includes(c.req.method) && c.req.header('X-Requested-With') !== 'camp') {
    throw new HttpError(403, 'طلب غير موثوق');
  }
  await next();
};

export const requireAuth = async (c, next) => {
  const user = await userFromRequest(c);
  if (!user) throw new HttpError(401, 'سجّل الدخول أولاً');
  c.set('user', user);
  await next();
};

export const isManager = (user) => user?.role === 'manager';

export function assertManager(user) {
  if (!isManager(user)) throw forbidden('هذا الإجراء للمدير فقط');
}

export const requireManager = async (c, next) => {
  assertManager(c.get('user'));
  await next();
};

/** Public profile for lists (no secrets, no private settings). */
export function publicUser(u) {
  return {
    id: u.id,
    username: u.username,
    name: u.name,
    role: u.role,
    specialty: u.specialty,
    phone: u.phone,
    color: u.color,
    sortOrder: u.sort_order,
    archivedAt: u.archived_at,
    distributionBalance: u.distribution_balance,
  };
}

export function selfUser(u) {
  let settings = {};
  try {
    settings = JSON.parse(u.settings || '{}');
  } catch {
    settings = {};
  }
  return { ...publicUser(u), mustChangePassword: Boolean(u.must_change_password), settings };
}
