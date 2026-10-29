import { Hono } from 'hono';
import { addDays } from '@camp/domain';
import { assertManager, endSession, hashPassword, requireAuth, selfUser, startSession, verifyPassword } from '../lib/auth.js';
import { all, first, getSetting, nowIso, run, setSetting } from '../lib/db.js';
import { HttpError, badRequest, readJson } from '../lib/http.js';
import { parse, v } from '../lib/validate.js';

const auth = new Hono();

const USERNAME = v.string({ min: 3, max: 32 });
const PASSWORD = v.string({ min: 8, max: 128 });

function checkUsername(username) {
  if (!/^[a-zA-Z0-9_.-]+$/.test(username)) {
    throw badRequest('اسم المستخدم بالأحرف الإنجليزية والأرقام فقط', { username: 'اسم المستخدم بالأحرف الإنجليزية والأرقام فقط' });
  }
  return username.toLowerCase();
}

auth.get('/setup/status', async (c) => {
  const row = await first(c.env.DB, 'SELECT COUNT(*) AS n FROM users');
  return c.json({ needsSetup: row.n === 0, campName: await getSetting(c.env.DB, 'camp_name', 'معسكر نقلة') });
});

/** First run only: creates the manager account. */
auth.post('/setup', async (c) => {
  const body = parse(await readJson(c), {
    campName: v.string({ max: 60, optional: true }),
    name: v.string({ min: 2, max: 60 }),
    username: USERNAME,
    password: PASSWORD,
  });
  const username = checkUsername(body.username);
  const count = await first(c.env.DB, 'SELECT COUNT(*) AS n FROM users');
  if (count.n > 0) throw new HttpError(409, 'تم إعداد النظام مسبقاً');
  const now = nowIso();
  const hash = await hashPassword(body.password);
  const r = await run(
    c.env.DB,
    `INSERT INTO users (username, name, role, password_hash, color, created_at, updated_at)
     VALUES (?, ?, 'manager', ?, '#243F35', ?, ?)`,
    username,
    body.name,
    hash,
    now,
    now,
  );
  await setSetting(c.env.DB, 'camp_name', body.campName || 'معسكر نقلة');
  const user = await first(c.env.DB, 'SELECT * FROM users WHERE id = ?', r.meta.last_row_id);
  await startSession(c, user, true);
  return c.json({ user: selfUser(user) }, 201);
});

auth.post('/auth/login', async (c) => {
  const body = parse(await readJson(c), {
    username: v.string({ max: 64 }),
    password: v.string({ max: 128 }),
    remember: v.bool({ defaultValue: false }),
  });
  const username = body.username.toLowerCase();
  const ip = c.req.header('CF-Connecting-IP') || 'local';
  const since = new Date(Date.now() - 15 * 60000).toISOString();
  // 5 failures per account; 30 per IP (the 8 members usually share one home connection).
  const attempts = await first(
    c.env.DB,
    `SELECT SUM(CASE WHEN key = ? THEN 1 ELSE 0 END) AS byUser, SUM(CASE WHEN key = ? THEN 1 ELSE 0 END) AS byIp
     FROM login_attempts WHERE (key = ? OR key = ?) AND created_at > ?`,
    `u:${username}`,
    `ip:${ip}`,
    `u:${username}`,
    `ip:${ip}`,
    since,
  );
  if ((attempts.byUser || 0) >= 5 || (attempts.byIp || 0) >= 30) throw new HttpError(429, 'محاولات كثيرة. حاول بعد 15 دقيقة');

  const user = await first(c.env.DB, 'SELECT * FROM users WHERE username = ? AND deleted_at IS NULL', username);
  const ok = user ? await verifyPassword(body.password, user.password_hash) : await verifyPassword(body.password, 'pbkdf2$100000$AAAAAAAAAAAAAAAAAAAAAA==$AA==');
  if (!user || !ok) {
    const now = nowIso();
    await run(c.env.DB, 'INSERT INTO login_attempts (key, created_at) VALUES (?, ?), (?, ?)', `u:${username}`, now, `ip:${ip}`, now);
    throw new HttpError(401, 'اسم المستخدم أو كلمة المرور غير صحيحة');
  }
  if (user.archived_at) throw new HttpError(403, 'هذا الحساب مؤرشف. تواصل مع المدير');
  await run(c.env.DB, 'DELETE FROM login_attempts WHERE key = ?', `u:${username}`);
  await startSession(c, user, body.remember);
  return c.json({ user: selfUser(user) });
});

auth.post('/auth/logout', async (c) => {
  endSession(c);
  return c.json({ ok: true });
});

auth.get('/auth/me', requireAuth, async (c) => {
  return c.json({ user: selfUser(c.get('user')), campName: await getSetting(c.env.DB, 'camp_name', 'معسكر نقلة') });
});

auth.post('/auth/password', requireAuth, async (c) => {
  const user = c.get('user');
  const body = parse(await readJson(c), { current: v.string({ max: 128 }), password: PASSWORD });
  if (!(await verifyPassword(body.current, user.password_hash))) {
    throw badRequest('كلمة المرور الحالية غير صحيحة', { current: 'كلمة المرور الحالية غير صحيحة' });
  }
  if (body.current === body.password) throw badRequest('اختر كلمة مرور مختلفة', { password: 'اختر كلمة مرور مختلفة' });
  const hash = await hashPassword(body.password);
  await run(
    c.env.DB,
    'UPDATE users SET password_hash = ?, session_version = session_version + 1, must_change_password = 0, updated_at = ? WHERE id = ?',
    hash,
    nowIso(),
    user.id,
  );
  const fresh = await first(c.env.DB, 'SELECT * FROM users WHERE id = ?', user.id);
  await startSession(c, fresh, true);
  return c.json({ ok: true });
});

const NOTIFICATION_PREFS = {
  disabled: v.array(v.string({ max: 40 }), { max: 30, optional: true }),
  quietFrom: v.time({ optional: true }),
  quietTo: v.time({ optional: true }),
};

auth.patch('/me', requireAuth, async (c) => {
  const user = c.get('user');
  const body = parse(
    await readJson(c),
    {
      name: v.string({ min: 2, max: 60 }),
      phone: v.string({ max: 30, optional: true }),
      settings: v.object(
        {
          theme: v.enum(['light', 'dark', 'system'], { optional: true }),
          sleepFrom: v.time({ optional: true }),
          sleepTo: v.time({ optional: true }),
          workoutsPerWeek: v.int({ min: 0, max: 7, optional: true }),
          hideAmounts: v.bool({ optional: true }),
          notifications: v.object(NOTIFICATION_PREFS, { optional: true }),
        },
        { optional: true },
      ),
    },
    { partial: true },
  );
  const current = JSON.parse(user.settings || '{}');
  const settings = { ...current };
  if (body.settings) {
    for (const [k, val] of Object.entries(body.settings)) {
      if (val === null) continue;
      settings[k] = k === 'notifications' ? { ...(current.notifications || {}), ...val } : val;
    }
  }
  await run(
    c.env.DB,
    'UPDATE users SET name = ?, phone = ?, settings = ?, updated_at = ? WHERE id = ?',
    body.name ?? user.name,
    body.phone !== undefined ? body.phone : user.phone,
    JSON.stringify(settings),
    nowIso(),
    user.id,
  );
  const fresh = await first(c.env.DB, 'SELECT * FROM users WHERE id = ?', user.id);
  return c.json({ user: selfUser(fresh) });
});

auth.patch('/camp', requireAuth, async (c) => {
  assertManager(c.get('user'));
  const body = parse(await readJson(c), { campName: v.string({ max: 60 }) });
  await setSetting(c.env.DB, 'camp_name', body.campName);
  return c.json({ campName: body.campName });
});

/** Personal data export (the user's own data only). */
auth.get('/me/export', requireAuth, async (c) => {
  const id = c.get('user').id;
  const db = c.env.DB;
  const q = (table, col = 'user_id') => all(db, `SELECT * FROM ${table} WHERE ${col} = ?`, id);
  const data = {
    exportedAt: nowIso(),
    profile: selfUser(c.get('user')),
    tasks: await all(db, 'SELECT * FROM tasks WHERE assignee_id = ? OR (kind = ? AND created_by = ?)', id, 'personal', id),
    prayers: await q('prayer_logs'),
    sleep: await q('sleep_logs'),
    workouts: await q('workouts'),
    goals: await q('goals'),
    goalSteps: await all(db, 'SELECT s.* FROM goal_steps s JOIN goals g ON g.id = s.goal_id WHERE g.user_id = ?', id),
    habits: await q('habits'),
    habitLogs: await all(db, 'SELECT l.* FROM habit_logs l JOIN habits h ON h.id = l.habit_id WHERE h.user_id = ?', id),
    budgetWeeks: await q('budget_weeks'),
    budgetIncomes: await q('budget_incomes'),
    budgetEssentials: await q('budget_essentials'),
    budgetExpenses: await q('budget_expenses'),
  };
  c.header('Content-Disposition', `attachment; filename="my-data-${addDays(new Date().toISOString().slice(0, 10), 0)}.json"`);
  return c.json(data);
});

export default auth;
