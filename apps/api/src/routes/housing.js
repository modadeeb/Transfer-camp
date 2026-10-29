import { Hono } from 'hono';
import { TASKS, addDays, count, formatDate, generateDistribution, isDate, settleBalances, weekStartOf } from '@camp/domain';
import { assertManager } from '../lib/auth.js';
import { all, batch, camel, camelAll, first, inList, logActivity, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, notFound, parseId, readJson } from '../lib/http.js';
import { fromRequest, notify } from '../lib/notify.js';
import { insertTask } from '../lib/tasks.js';
import { parse, v } from '../lib/validate.js';
import { activeMembers } from './members.js';

const housing = new Hono();

export const SLOT_DUE_TIME = { morning: '12:00', afternoon: '17:00', evening: '22:00', any: null };

const choreSchema = {
  name: v.string({ min: 2, max: 60 }),
  icon: v.string({ max: 40, optional: true }),
  frequency: v.enum(['daily', 'days', 'weekly']),
  days: v.array(v.int({ min: 0, max: 6 }), { max: 7, optional: true }),
  weeklyDay: v.int({ min: 0, max: 6, optional: true }),
  points: v.int({ min: 1, max: 5 }),
  peopleCount: v.int({ min: 1, max: 8, defaultValue: 1 }),
  slot: v.enum(['morning', 'afternoon', 'evening', 'any'], { defaultValue: 'any' }),
  active: v.bool({ defaultValue: true }),
};

function checkChore(c) {
  if (c.frequency === 'days' && !(c.days || []).length) throw badRequest('اختر أيام التكرار', { days: 'اختر أيام التكرار' });
}

const loadChore = async (db, id, { includeDeleted = false } = {}) => {
  const row = await first(db, `SELECT * FROM chores WHERE id = ? ${includeDeleted ? '' : 'AND deleted_at IS NULL'}`, id);
  if (!row) throw notFound('المهمة المنزلية غير موجودة');
  return row;
};

housing.get('/chores', async (c) => {
  const archived = c.req.query('archived') === '1';
  const rows = await all(
    c.env.DB,
    `SELECT * FROM chores WHERE deleted_at IS NULL AND archived_at IS ${archived ? 'NOT NULL' : 'NULL'} ORDER BY sort_order, id`,
  );
  return c.json({ chores: camelAll(rows) });
});

housing.post('/chores', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const b = parse(await readJson(c), choreSchema);
  checkChore(b);
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM chores');
  const now = nowIso();
  const r = await run(
    c.env.DB,
    `INSERT INTO chores (name, icon, frequency, days, weekly_day, points, people_count, slot, active, sort_order, created_by, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    b.name,
    b.icon,
    b.frequency,
    JSON.stringify(b.frequency === 'days' ? b.days : []),
    b.frequency === 'weekly' ? (b.weeklyDay ?? 6) : null,
    b.points,
    b.peopleCount,
    b.slot,
    b.active,
    mx.mx + 1,
    me.id,
    now,
    now,
  );
  await logActivity(c.env.DB, 'chore', r.meta.last_row_id, me.id, 'created');
  return c.json({ chore: camel(await loadChore(c.env.DB, r.meta.last_row_id)) }, 201);
});

housing.patch('/chores/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadChore(c.env.DB, parseId(c.req.param('id')));
  const b = parse(await readJson(c), choreSchema, { partial: true });
  const merged = {
    name: b.name ?? row.name,
    icon: b.icon !== undefined ? b.icon : row.icon,
    frequency: b.frequency ?? row.frequency,
    days: b.days !== undefined ? b.days || [] : JSON.parse(row.days),
    weeklyDay: b.weeklyDay !== undefined ? b.weeklyDay : row.weekly_day,
    points: b.points ?? row.points,
    peopleCount: b.peopleCount ?? row.people_count,
    slot: b.slot ?? row.slot,
    active: b.active ?? Boolean(row.active),
  };
  checkChore(merged);
  await run(
    c.env.DB,
    `UPDATE chores SET name = ?, icon = ?, frequency = ?, days = ?, weekly_day = ?, points = ?, people_count = ?, slot = ?, active = ?, updated_at = ? WHERE id = ?`,
    merged.name,
    merged.icon,
    merged.frequency,
    JSON.stringify(merged.frequency === 'days' ? merged.days : []),
    merged.frequency === 'weekly' ? (merged.weeklyDay ?? 6) : null,
    merged.points,
    merged.peopleCount,
    merged.slot,
    merged.active,
    nowIso(),
    row.id,
  );
  await logActivity(c.env.DB, 'chore', row.id, me.id, 'updated', b);
  return c.json({ chore: camel(await loadChore(c.env.DB, row.id)) });
});

housing.post('/chores/:id/copy', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadChore(c.env.DB, parseId(c.req.param('id')));
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM chores');
  const now = nowIso();
  const r = await run(
    c.env.DB,
    `INSERT INTO chores (name, icon, frequency, days, weekly_day, points, people_count, slot, active, sort_order, created_by, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    `${row.name} (نسخة)`,
    row.icon,
    row.frequency,
    row.days,
    row.weekly_day,
    row.points,
    row.people_count,
    row.slot,
    row.active,
    mx.mx + 1,
    me.id,
    now,
    now,
  );
  return c.json({ chore: camel(await loadChore(c.env.DB, r.meta.last_row_id)) }, 201);
});

for (const [path, column, value] of [
  ['archive', 'archived_at', true],
  ['unarchive', 'archived_at', false],
  ['restore', 'deleted_at', false],
]) {
  housing.post(`/chores/:id/${path}`, async (c) => {
    const me = c.get('user');
    assertManager(me);
    const row = await loadChore(c.env.DB, parseId(c.req.param('id')), { includeDeleted: path === 'restore' });
    await run(c.env.DB, `UPDATE chores SET ${column} = ?, updated_at = ? WHERE id = ?`, value ? nowIso() : null, nowIso(), row.id);
    await logActivity(c.env.DB, 'chore', row.id, me.id, path);
    return c.json({ chore: camel(await loadChore(c.env.DB, row.id)) });
  });
}

housing.delete('/chores/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadChore(c.env.DB, parseId(c.req.param('id')));
  await run(c.env.DB, 'UPDATE chores SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
  await logActivity(c.env.DB, 'chore', row.id, me.id, 'deleted');
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- distribution

function normalizeWeek(param) {
  if (!isDate(param)) throw badRequest('تاريخ الأسبوع غير صالح');
  return weekStartOf(param);
}

export async function distributionView(db, weekStart) {
  const dist = await first(db, 'SELECT * FROM distributions WHERE week_start = ?', weekStart);
  const members = await activeMembers(db);
  if (!dist) {
    return {
      weekStart,
      distribution: null,
      items: [],
      summary: members.map((m) => ({ userId: m.id, name: m.name, color: m.color, points: 0, balance: m.distribution_balance })),
      unassigned: 0,
    };
  }
  const items = await all(
    db,
    `SELECT i.*, c.name AS chore_name, c.icon AS chore_icon, u.name AS user_name, u.color AS user_color, t.status AS task_status
     FROM distribution_items i JOIN chores c ON c.id = i.chore_id
     LEFT JOIN users u ON u.id = i.user_id LEFT JOIN tasks t ON t.id = i.task_id
     WHERE i.distribution_id = ? ORDER BY i.date, c.sort_order, i.chore_id, i.id`,
    dist.id,
  );
  const balances = await all(db, 'SELECT * FROM distribution_balances WHERE distribution_id = ?', dist.id);
  const summary = members.map((m) => {
    const b = balances.find((x) => x.user_id === m.id);
    return {
      userId: m.id,
      name: m.name,
      color: m.color,
      points: items.filter((i) => i.user_id === m.id).reduce((s, i) => s + i.points, 0),
      balance: b ? b.balance_before : m.distribution_balance,
      balanceAfter: b ? b.balance_after : null,
    };
  });
  return {
    weekStart,
    distribution: camel(dist),
    items: camelAll(items),
    summary,
    unassigned: items.filter((i) => i.user_id == null).length,
  };
}

/** Builds (or rebuilds) the draft for a week. Shared by the API and the weekly cron. */
export async function buildDraft(db, weekStart) {
  const existing = await first(db, 'SELECT * FROM distributions WHERE week_start = ?', weekStart);
  if (existing?.status === 'published') throw conflict('توزيع هذا الأسبوع منشور مسبقاً');
  const weekEnd = addDays(weekStart, 6);
  const users = await activeMembers(db);
  if (!users.length) throw badRequest('لا يوجد أعضاء');
  const slots = await all(db, `SELECT * FROM member_slots WHERE user_id IN (${inList(users.map((u) => u.id))})`, ...users.map((u) => u.id));
  const absences = await all(
    db,
    'SELECT user_id, start_date, end_date FROM absences WHERE deleted_at IS NULL AND start_date <= ? AND end_date >= ?',
    weekEnd,
    weekStart,
  );
  const chores = await all(db, 'SELECT * FROM chores WHERE deleted_at IS NULL AND archived_at IS NULL AND active = 1 ORDER BY sort_order, id');
  if (!chores.length) throw badRequest('أضف مهام السكن أولاً');
  const prev = await first(db, "SELECT id FROM distributions WHERE week_start = ? AND status = 'published'", addDays(weekStart, -7));
  const previous = prev
    ? (await all(db, 'SELECT chore_id, user_id FROM distribution_items WHERE distribution_id = ? AND user_id IS NOT NULL', prev.id)).map((p) => ({
        choreId: p.chore_id,
        userId: p.user_id,
      }))
    : [];

  const result = generateDistribution({
    weekStart,
    members: users.map((u) => ({
      id: u.id,
      sortOrder: u.sort_order,
      balance: u.distribution_balance,
      busy: slots.filter((s) => s.user_id === u.id).map((s) => ({ dow: s.dow, start: s.start_time, end: s.end_time })),
    })),
    chores: chores.map((ch) => ({
      id: ch.id,
      points: ch.points,
      frequency: ch.frequency,
      days: JSON.parse(ch.days || '[]'),
      weeklyDay: ch.weekly_day,
      slot: ch.slot,
      peopleCount: ch.people_count,
      sortOrder: ch.sort_order,
    })),
    previous,
    absences: absences.map((a) => ({ userId: a.user_id, startDate: a.start_date, endDate: a.end_date })),
  });

  const now = nowIso();
  let distId = existing?.id;
  if (!distId) {
    const r = await run(db, "INSERT INTO distributions (week_start, status, generated_at) VALUES (?, 'draft', ?)", weekStart, now);
    distId = r.meta.last_row_id;
  } else {
    await run(db, 'UPDATE distributions SET generated_at = ? WHERE id = ?', now, distId);
  }
  await batch(db, [
    ['DELETE FROM distribution_items WHERE distribution_id = ?', distId],
    ...result.items.map((i) => [
      'INSERT INTO distribution_items (distribution_id, chore_id, date, slot, user_id, points) VALUES (?, ?, ?, ?, ?, ?)',
      distId,
      i.choreId,
      i.date,
      i.slot,
      i.userId,
      i.points,
    ]),
  ]);
  return distId;
}

housing.get('/distributions/:weekStart', async (c) => {
  return c.json(await distributionView(c.env.DB, normalizeWeek(c.req.param('weekStart'))));
});

housing.post('/distributions/:weekStart/generate', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const weekStart = normalizeWeek(c.req.param('weekStart'));
  const id = await buildDraft(c.env.DB, weekStart);
  await logActivity(c.env.DB, 'distribution', id, me.id, 'generated');
  return c.json(await distributionView(c.env.DB, weekStart));
});

housing.patch('/distribution-items/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const item = await first(
    c.env.DB,
    'SELECT i.*, d.status, d.week_start FROM distribution_items i JOIN distributions d ON d.id = i.distribution_id WHERE i.id = ?',
    parseId(c.req.param('id')),
  );
  if (!item) throw notFound();
  if (item.status !== 'draft') throw conflict('التوزيع منشور؛ عدّل المهمة نفسها من قائمة المهام');
  const b = parse(await readJson(c), { userId: v.id({ optional: true }) });
  if (b.userId) {
    const u = await first(c.env.DB, 'SELECT id FROM users WHERE id = ? AND deleted_at IS NULL AND archived_at IS NULL', b.userId);
    if (!u) throw badRequest('العضو غير موجود');
    const clash = await first(
      c.env.DB,
      'SELECT id FROM distribution_items WHERE distribution_id = ? AND chore_id = ? AND date = ? AND user_id = ? AND id != ?',
      item.distribution_id,
      item.chore_id,
      item.date,
      b.userId,
      item.id,
    );
    if (clash) throw conflict('هذا العضو مسند لنفس المهمة في نفس اليوم');
  }
  await run(c.env.DB, 'UPDATE distribution_items SET user_id = ? WHERE id = ?', b.userId, item.id);
  return c.json(await distributionView(c.env.DB, item.week_start));
});

housing.post('/distributions/:weekStart/publish', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const db = c.env.DB;
  const weekStart = normalizeWeek(c.req.param('weekStart'));
  const dist = await first(db, 'SELECT * FROM distributions WHERE week_start = ?', weekStart);
  if (!dist) throw notFound('لا توجد مسودة لهذا الأسبوع');
  if (dist.status === 'published') throw conflict('التوزيع منشور مسبقاً');
  const items = await all(
    db,
    'SELECT i.*, c.name AS chore_name FROM distribution_items i JOIN chores c ON c.id = i.chore_id WHERE i.distribution_id = ? ORDER BY i.date, i.id',
    dist.id,
  );
  const missing = items.filter((i) => i.user_id == null).length;
  if (missing) throw badRequest(`يوجد ${missing} مهمة بلا مكلَّف. أسندها قبل النشر`);
  if (!items.length) throw badRequest('المسودة فارغة');

  // Lock first so a double click can't publish twice.
  const lock = await run(db, "UPDATE distributions SET status = 'published', published_at = ?, published_by = ? WHERE id = ? AND status = 'draft'", nowIso(), me.id, dist.id);
  if (!lock.meta.changes) throw conflict('التوزيع منشور مسبقاً');

  for (const i of items) {
    const taskId = await insertTask(db, {
      kind: 'house',
      title: i.chore_name,
      assignee_id: i.user_id,
      chore_id: i.chore_id,
      distribution_item_id: i.id,
      due_date: i.date,
      due_time: SLOT_DUE_TIME[i.slot] ?? null,
      size: i.points,
      needs_approval: 0,
      created_by: me.id,
    });
    await run(db, 'UPDATE distribution_items SET task_id = ? WHERE id = ?', taskId, i.id);
  }

  const members = await activeMembers(db);
  const settled = settleBalances(
    members.map((m) => ({ id: m.id, balance: m.distribution_balance })),
    items.map((i) => ({ userId: i.user_id, points: i.points })),
  );
  await batch(db, [
    ...settled.map((s) => [
      'INSERT INTO distribution_balances (distribution_id, user_id, assigned, expected, balance_before, balance_after) VALUES (?, ?, ?, ?, ?, ?)',
      dist.id,
      s.userId,
      s.assigned,
      s.expected,
      s.balanceBefore,
      s.balanceAfter,
    ]),
    ...settled.map((s) => ['UPDATE users SET distribution_balance = ? WHERE id = ?', s.balanceAfter, s.userId]),
  ]);
  await logActivity(db, 'distribution', dist.id, me.id, 'published');

  const ctx = fromRequest(c);
  for (const s of settled) {
    const mine = items.filter((i) => i.user_id === s.userId);
    if (!mine.length) continue;
    await notify(ctx, [s.userId], {
      type: 'distribution',
      title: 'نُشر توزيع مهام السكن',
      body: `أسبوع ${formatDate(weekStart)}: لديك ${count(mine.length, TASKS)} (${s.assigned} نقطة)`,
      link: `/housing?week=${weekStart}`,
    });
  }
  return c.json(await distributionView(db, weekStart));
});

export default housing;
