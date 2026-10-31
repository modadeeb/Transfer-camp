// Personal data. Every query is scoped to the signed-in user; nobody else (manager included) can read it.
import { Hono } from 'hono';
import { addDays, adenDate, currentStreak, isDate, sleepMinutes, weekDots, weekStartOf } from '@camp/domain';
import { all, camel, camelAll, first, nowIso, run } from '../lib/db.js';
import { badRequest, notFound, parseId, readJson } from '../lib/http.js';
import { prayerTimes } from '../lib/prayers.js';
import { parse, v } from '../lib/validate.js';

const personal = new Hono();
const PRAYERS = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

function range(c) {
  const today = adenDate();
  const from = isDate(c.req.query('from')) ? c.req.query('from') : weekStartOf(today);
  const to = isDate(c.req.query('to')) ? c.req.query('to') : addDays(from, 6);
  return { from, to, today };
}

// ---------------------------------------------------------------- prayers
personal.get('/me/prayers', async (c) => {
  const { from, to } = range(c);
  const rows = await all(c.env.DB, 'SELECT date, prayer FROM prayer_logs WHERE user_id = ? AND date BETWEEN ? AND ? ORDER BY date', c.get('user').id, from, to);
  const times = {};
  for (let d = from; d <= to && Object.keys(times).length < 62; d = addDays(d, 1)) times[d] = prayerTimes(d);
  return c.json({ from, to, logs: rows, times });
});

personal.put('/me/prayers', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { date: v.date(), prayer: v.enum(PRAYERS), done: v.bool() });
  if (b.date > adenDate()) throw badRequest('لا يمكن تسجيل صلاة في المستقبل');
  if (b.done) await run(c.env.DB, 'INSERT OR IGNORE INTO prayer_logs (user_id, date, prayer) VALUES (?, ?, ?)', me.id, b.date, b.prayer);
  else await run(c.env.DB, 'DELETE FROM prayer_logs WHERE user_id = ? AND date = ? AND prayer = ?', me.id, b.date, b.prayer);
  const rows = await all(c.env.DB, 'SELECT prayer FROM prayer_logs WHERE user_id = ? AND date = ?', me.id, b.date);
  return c.json({ date: b.date, done: rows.map((r) => r.prayer) });
});

// ---------------------------------------------------------------- sleep
personal.get('/me/sleep', async (c) => {
  const { from, to } = range(c);
  const rows = await all(c.env.DB, 'SELECT * FROM sleep_logs WHERE user_id = ? AND date BETWEEN ? AND ? ORDER BY date', c.get('user').id, from, to);
  return c.json({ from, to, logs: rows.map((r) => ({ ...camel(r), minutes: sleepMinutes(r.slept_at, r.woke_at) })) });
});

personal.put('/me/sleep', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { date: v.date(), sleptAt: v.time(), wokeAt: v.time() });
  if (b.date > adenDate()) throw badRequest('لا يمكن تسجيل نوم في المستقبل');
  await run(
    c.env.DB,
    'INSERT INTO sleep_logs (user_id, date, slept_at, woke_at) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET slept_at = excluded.slept_at, woke_at = excluded.woke_at',
    me.id,
    b.date,
    b.sleptAt,
    b.wokeAt,
  );
  return c.json({ log: { ...b, minutes: sleepMinutes(b.sleptAt, b.wokeAt) } });
});

personal.delete('/me/sleep/:date', async (c) => {
  const date = c.req.param('date');
  if (!isDate(date)) throw notFound();
  await run(c.env.DB, 'DELETE FROM sleep_logs WHERE user_id = ? AND date = ?', c.get('user').id, date);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- workouts
personal.get('/me/workouts', async (c) => {
  const { from, to } = range(c);
  const rows = await all(c.env.DB, 'SELECT * FROM workouts WHERE user_id = ? AND date BETWEEN ? AND ? ORDER BY date, id', c.get('user').id, from, to);
  return c.json({ from, to, workouts: camelAll(rows) });
});

personal.post('/me/workouts', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { date: v.date({ optional: true }), type: v.string({ max: 40 }), durationMin: v.int({ min: 1, max: 600, optional: true }) });
  const date = b.date || adenDate();
  if (date > adenDate()) throw badRequest('لا يمكن تسجيل تمرين في المستقبل');
  const r = await run(c.env.DB, 'INSERT INTO workouts (user_id, date, type, duration_min, created_at) VALUES (?, ?, ?, ?, ?)', me.id, date, b.type, b.durationMin, nowIso());
  return c.json({ workout: camel(await first(c.env.DB, 'SELECT * FROM workouts WHERE id = ?', r.meta.last_row_id)) }, 201);
});

personal.delete('/me/workouts/:id', async (c) => {
  const r = await run(c.env.DB, 'DELETE FROM workouts WHERE id = ? AND user_id = ?', parseId(c.req.param('id')), c.get('user').id);
  if (!r.meta.changes) throw notFound();
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- goals
const GOAL_CATEGORIES = ['religious', 'study', 'health', 'money', 'work', 'personal'];

async function loadGoal(db, id, userId, { includeDeleted = false } = {}) {
  const g = await first(db, `SELECT * FROM goals WHERE id = ? AND user_id = ? ${includeDeleted ? '' : 'AND deleted_at IS NULL'}`, id, userId);
  if (!g) throw notFound('الهدف غير موجود');
  return g;
}

async function goalWithSteps(db, g) {
  const steps = await all(db, 'SELECT * FROM goal_steps WHERE goal_id = ? ORDER BY sort_order, id', g.id);
  const done = steps.filter((s) => s.done_at).length;
  return { ...camel(g), steps: camelAll(steps), progress: steps.length ? Math.round((done / steps.length) * 100) : 0 };
}

personal.get('/me/goals', async (c) => {
  const archived = c.req.query('archived') === '1';
  const rows = await all(
    c.env.DB,
    `SELECT * FROM goals WHERE user_id = ? AND deleted_at IS NULL AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'} ORDER BY sort_order, id`,
    c.get('user').id,
  );
  const goals = [];
  for (const g of rows) goals.push(await goalWithSteps(c.env.DB, g));
  return c.json({ goals });
});

const goalSchema = {
  title: v.string({ min: 2, max: 100 }),
  category: v.enum(GOAL_CATEGORIES, { defaultValue: 'personal' }),
  targetDate: v.date({ optional: true }),
  steps: v.array(v.string({ max: 120 }), { max: 30, optional: true }),
};

personal.post('/me/goals', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), goalSchema);
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM goals WHERE user_id = ?', me.id);
  const now = nowIso();
  const r = await run(
    c.env.DB,
    'INSERT INTO goals (user_id, title, category, target_date, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    me.id,
    b.title,
    b.category,
    b.targetDate,
    mx.mx + 1,
    now,
    now,
  );
  const id = r.meta.last_row_id;
  for (const [i, title] of (b.steps || []).entries()) {
    await run(c.env.DB, 'INSERT INTO goal_steps (goal_id, title, sort_order) VALUES (?, ?, ?)', id, title, i);
  }
  return c.json({ goal: await goalWithSteps(c.env.DB, await loadGoal(c.env.DB, id, me.id)) }, 201);
});

personal.patch('/me/goals/:id', async (c) => {
  const me = c.get('user');
  const g = await loadGoal(c.env.DB, parseId(c.req.param('id')), me.id);
  const { steps: _s, ...editable } = goalSchema;
  const b = parse(await readJson(c), editable, { partial: true });
  await run(
    c.env.DB,
    'UPDATE goals SET title = ?, category = ?, target_date = ?, updated_at = ? WHERE id = ?',
    b.title ?? g.title,
    b.category ?? g.category,
    b.targetDate !== undefined ? b.targetDate : g.target_date,
    nowIso(),
    g.id,
  );
  return c.json({ goal: await goalWithSteps(c.env.DB, await loadGoal(c.env.DB, g.id, me.id)) });
});

for (const [path, column, value] of [
  ['archive', 'archived_at', true],
  ['unarchive', 'archived_at', false],
  ['restore', 'deleted_at', false],
]) {
  personal.post(`/me/goals/:id/${path}`, async (c) => {
    const me = c.get('user');
    const g = await loadGoal(c.env.DB, parseId(c.req.param('id')), me.id, { includeDeleted: path === 'restore' });
    await run(c.env.DB, `UPDATE goals SET ${column} = ?, updated_at = ? WHERE id = ?`, value ? nowIso() : null, nowIso(), g.id);
    return c.json({ goal: await goalWithSteps(c.env.DB, await loadGoal(c.env.DB, g.id, me.id)) });
  });
}

personal.delete('/me/goals/:id', async (c) => {
  const me = c.get('user');
  const g = await loadGoal(c.env.DB, parseId(c.req.param('id')), me.id);
  await run(c.env.DB, 'UPDATE goals SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), g.id);
  return c.json({ ok: true });
});

personal.post('/me/goals/:id/steps', async (c) => {
  const me = c.get('user');
  const g = await loadGoal(c.env.DB, parseId(c.req.param('id')), me.id);
  const b = parse(await readJson(c), { title: v.string({ max: 120 }) });
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), -1) AS mx FROM goal_steps WHERE goal_id = ?', g.id);
  await run(c.env.DB, 'INSERT INTO goal_steps (goal_id, title, sort_order) VALUES (?, ?, ?)', g.id, b.title, mx.mx + 1);
  return c.json({ goal: await goalWithSteps(c.env.DB, g) }, 201);
});

async function loadStep(db, id, userId) {
  const s = await first(
    db,
    'SELECT s.*, g.id AS gid FROM goal_steps s JOIN goals g ON g.id = s.goal_id WHERE s.id = ? AND g.user_id = ? AND g.deleted_at IS NULL',
    id,
    userId,
  );
  if (!s) throw notFound('الخطوة غير موجودة');
  return s;
}

personal.patch('/me/goal-steps/:id', async (c) => {
  const me = c.get('user');
  const s = await loadStep(c.env.DB, parseId(c.req.param('id')), me.id);
  const b = parse(await readJson(c), { title: v.string({ max: 120 }), done: v.bool() }, { partial: true });
  await run(
    c.env.DB,
    'UPDATE goal_steps SET title = ?, done_at = ? WHERE id = ?',
    b.title ?? s.title,
    b.done === undefined ? s.done_at : b.done ? s.done_at || nowIso() : null,
    s.id,
  );
  return c.json({ goal: await goalWithSteps(c.env.DB, await loadGoal(c.env.DB, s.gid, me.id)) });
});

personal.delete('/me/goal-steps/:id', async (c) => {
  const me = c.get('user');
  const s = await loadStep(c.env.DB, parseId(c.req.param('id')), me.id);
  await run(c.env.DB, 'DELETE FROM goal_steps WHERE id = ?', s.id);
  return c.json({ goal: await goalWithSteps(c.env.DB, await loadGoal(c.env.DB, s.gid, me.id)) });
});

// ---------------------------------------------------------------- habits
const daysRule = (value) => {
  if (value === 'daily') return 'daily';
  if (Array.isArray(value) && value.length && value.every((d) => Number.isInteger(d) && d >= 0 && d <= 6)) return [...new Set(value)].sort();
  throw new Error('اختر أيام العادة');
};

async function loadHabit(db, id, userId, { includeDeleted = false } = {}) {
  const h = await first(db, `SELECT * FROM habits WHERE id = ? AND user_id = ? ${includeDeleted ? '' : 'AND deleted_at IS NULL'}`, id, userId);
  if (!h) throw notFound('العادة غير موجودة');
  return h;
}

async function habitView(db, h, today) {
  const logs = await all(db, 'SELECT date FROM habit_logs WHERE habit_id = ? AND date >= ? ORDER BY date', h.id, addDays(today, -400));
  const habit = camel(h);
  const dates = logs.map((l) => l.date);
  return {
    ...habit,
    doneToday: dates.includes(today),
    streak: currentStreak(habit, dates, today),
    week: weekDots(habit, dates, weekStartOf(today)),
    last30: dates.filter((d) => d > addDays(today, -30)),
  };
}

personal.get('/me/habits', async (c) => {
  const me = c.get('user');
  const today = adenDate();
  const archived = c.req.query('archived') === '1';
  const rows = await all(
    c.env.DB,
    `SELECT * FROM habits WHERE user_id = ? AND deleted_at IS NULL AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'} ORDER BY sort_order, id`,
    me.id,
  );
  const habits = [];
  for (const h of rows) habits.push(await habitView(c.env.DB, h, today));
  return c.json({ today, habits });
});

personal.post('/me/habits', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { title: v.string({ min: 2, max: 80 }), days: { check: daysRule, optional: false } });
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM habits WHERE user_id = ?', me.id);
  const now = nowIso();
  const r = await run(
    c.env.DB,
    'INSERT INTO habits (user_id, title, days, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    me.id,
    b.title,
    JSON.stringify(b.days),
    mx.mx + 1,
    now,
    now,
  );
  return c.json({ habit: await habitView(c.env.DB, await loadHabit(c.env.DB, r.meta.last_row_id, me.id), adenDate()) }, 201);
});

personal.patch('/me/habits/:id', async (c) => {
  const me = c.get('user');
  const h = await loadHabit(c.env.DB, parseId(c.req.param('id')), me.id);
  const b = parse(await readJson(c), { title: v.string({ min: 2, max: 80 }), days: { check: daysRule, optional: false } }, { partial: true });
  await run(
    c.env.DB,
    'UPDATE habits SET title = ?, days = ?, updated_at = ? WHERE id = ?',
    b.title ?? h.title,
    b.days !== undefined ? JSON.stringify(b.days) : h.days,
    nowIso(),
    h.id,
  );
  return c.json({ habit: await habitView(c.env.DB, await loadHabit(c.env.DB, h.id, me.id), adenDate()) });
});

personal.post('/me/habits/:id/toggle', async (c) => {
  const me = c.get('user');
  const h = await loadHabit(c.env.DB, parseId(c.req.param('id')), me.id);
  const b = parse(await readJson(c), { date: v.date({ optional: true }), done: v.bool() });
  const date = b.date || adenDate();
  if (date > adenDate()) throw badRequest('لا يمكن التسجيل في المستقبل');
  if (b.done) await run(c.env.DB, 'INSERT OR IGNORE INTO habit_logs (habit_id, date) VALUES (?, ?)', h.id, date);
  else await run(c.env.DB, 'DELETE FROM habit_logs WHERE habit_id = ? AND date = ?', h.id, date);
  return c.json({ habit: await habitView(c.env.DB, h, adenDate()) });
});

for (const [path, column, value] of [
  ['archive', 'archived_at', true],
  ['unarchive', 'archived_at', false],
  ['restore', 'deleted_at', false],
]) {
  personal.post(`/me/habits/:id/${path}`, async (c) => {
    const me = c.get('user');
    const h = await loadHabit(c.env.DB, parseId(c.req.param('id')), me.id, { includeDeleted: path === 'restore' });
    await run(c.env.DB, `UPDATE habits SET ${column} = ?, updated_at = ? WHERE id = ?`, value ? nowIso() : null, nowIso(), h.id);
    return c.json({ habit: await habitView(c.env.DB, await loadHabit(c.env.DB, h.id, me.id), adenDate()) });
  });
}

personal.delete('/me/habits/:id', async (c) => {
  const me = c.get('user');
  const h = await loadHabit(c.env.DB, parseId(c.req.param('id')), me.id);
  await run(c.env.DB, 'UPDATE habits SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), h.id);
  return c.json({ ok: true });
});

export default personal;
