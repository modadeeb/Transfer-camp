import { readFileSync } from 'node:fs';
import { Miniflare } from 'miniflare';
import { app } from '../src/index.js';

const MIGRATION = readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8');

/** Split the migration into statements (no semicolons inside our SQL literals). */
function statements(sql) {
  return sql
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .join('\n')
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean);
}

export async function createEnv(extra = {}) {
  const mf = new Miniflare({ modules: true, script: 'export default {}', d1Databases: ['DB'] });
  const DB = await mf.getD1Database('DB');
  for (const s of statements(MIGRATION)) await DB.prepare(s).run();
  const env = { DB, JWT_SECRET: 'test-secret-test-secret-test-secret-1234', ...extra };
  return { env, mf };
}

/** A tiny client with its own cookie jar. */
export function client(env) {
  let cookie = '';
  const pending = [];
  const ctx = { waitUntil: (p) => pending.push(p), passThroughOnException() {} };
  async function request(method, path, body) {
    const headers = { 'X-Requested-With': 'camp' };
    if (cookie) headers.Cookie = cookie;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const res = await app.fetch(
      new Request(`http://localhost/api${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }),
      env,
      ctx,
    );
    const set = res.headers.get('Set-Cookie');
    if (set) {
      const [pair] = set.split(';');
      cookie = pair.endsWith('=') ? '' : pair;
    }
    await Promise.all(pending.splice(0));
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = text;
    }
    return { status: res.status, body: json, headers: res.headers };
  }
  return {
    get: (p) => request('GET', p),
    post: (p, b = {}) => request('POST', p, b),
    patch: (p, b = {}) => request('PATCH', p, b),
    put: (p, b = {}) => request('PUT', p, b),
    del: (p) => request('DELETE', p),
    raw: request,
    get cookie() {
      return cookie;
    },
  };
}

/** Manager + 7 members, logged in. */
export async function seedCamp(env) {
  const manager = client(env);
  const r = await manager.post('/setup', { campName: 'معسكر نقلة', name: 'محمد', username: 'mohamed', password: 'manager-pass-1' });
  if (r.status !== 201) throw new Error(`setup failed ${JSON.stringify(r.body)}`);
  const names = ['سالم', 'أحمد', 'علي', 'خالد', 'فهد', 'عمر', 'يوسف'];
  const specialties = ['backend', 'frontend', 'design', 'qa', 'frontend', 'backend', 'pm'];
  const members = [];
  for (const [i, name] of names.entries()) {
    const res = await manager.post('/members', { name, username: `member${i + 1}`, specialty: specialties[i] });
    if (res.status !== 201) throw new Error(`member failed ${JSON.stringify(res.body)}`);
    const c = client(env);
    const login = await c.post('/auth/login', { username: `member${i + 1}`, password: res.body.tempPassword });
    if (login.status !== 200) throw new Error('login failed');
    await c.post('/auth/password', { current: res.body.tempPassword, password: `member-pass-${i + 1}` });
    members.push({ id: res.body.member.id, name, client: c });
  }
  return { manager, managerId: r.body.user.id, members };
}
