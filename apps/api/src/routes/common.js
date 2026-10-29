// Notifications, devices, push config, trash, reorder and change history.
import { Hono } from 'hono';
import { isManager } from '../lib/auth.js';
import { all, batch, camelAll, first, inList, nowIso, run } from '../lib/db.js';
import { badRequest, forbidden, notFound, parseId, readJson } from '../lib/http.js';
import { NOTIFICATION_TYPES } from '../lib/notify.js';
import { parse, v } from '../lib/validate.js';

const common = new Hono();

// ---------------------------------------------------------------- notifications
common.get('/notifications', async (c) => {
  const me = c.get('user');
  const limit = Math.min(Number(c.req.query('limit')) || 50, 200);
  const rows = await all(
    c.env.DB,
    `SELECT * FROM notifications WHERE user_id = ? AND deleted_at IS NULL ${c.req.query('unread') === '1' ? 'AND read_at IS NULL' : ''}
     ORDER BY id DESC LIMIT ${limit}`,
    me.id,
  );
  const unread = await first(c.env.DB, 'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL', me.id);
  return c.json({ notifications: camelAll(rows), unread: unread.n, types: NOTIFICATION_TYPES });
});

common.post('/notifications/read-all', async (c) => {
  await run(c.env.DB, 'UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL', nowIso(), c.get('user').id);
  return c.json({ ok: true });
});

common.post('/notifications/:id/read', async (c) => {
  await run(c.env.DB, 'UPDATE notifications SET read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ?', nowIso(), parseId(c.req.param('id')), c.get('user').id);
  return c.json({ ok: true });
});

common.delete('/notifications/:id', async (c) => {
  const r = await run(c.env.DB, 'UPDATE notifications SET deleted_at = ? WHERE id = ? AND user_id = ? AND deleted_at IS NULL', nowIso(), parseId(c.req.param('id')), c.get('user').id);
  if (!r.meta.changes) throw notFound();
  return c.json({ ok: true });
});

common.post('/notifications/:id/restore', async (c) => {
  await run(c.env.DB, 'UPDATE notifications SET deleted_at = NULL WHERE id = ? AND user_id = ?', parseId(c.req.param('id')), c.get('user').id);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- push devices
common.get('/push/config', async (c) => {
  let firebase = null;
  try {
    firebase = c.env.FIREBASE_WEB_CONFIG ? JSON.parse(c.env.FIREBASE_WEB_CONFIG) : null;
  } catch {
    firebase = null;
  }
  const enabled = Boolean(firebase && c.env.FIREBASE_VAPID_KEY && c.env.FCM_SERVICE_ACCOUNT);
  return c.json({ enabled, firebase: enabled ? firebase : null, vapidKey: enabled ? c.env.FIREBASE_VAPID_KEY : null });
});

common.post('/devices', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { token: v.string({ min: 20, max: 4096 }), platform: v.string({ max: 40, optional: true }) });
  const now = nowIso();
  await run(
    c.env.DB,
    `INSERT INTO device_tokens (user_id, token, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, platform = excluded.platform, last_seen_at = excluded.last_seen_at`,
    me.id,
    b.token,
    b.platform,
    now,
    now,
  );
  return c.json({ ok: true });
});

common.post('/devices/remove', async (c) => {
  const b = parse(await readJson(c), { token: v.string({ min: 20, max: 4096 }) });
  await run(c.env.DB, 'DELETE FROM device_tokens WHERE token = ? AND user_id = ?', b.token, c.get('user').id);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- trash (30 days)
export const TRASH_DAYS = 30;

common.get('/trash', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const since = new Date(Date.now() - TRASH_DAYS * 86400000).toISOString();
  const mgr = isManager(me);
  const items = [];
  const push = (entity, label, rows, titleKey = 'title') =>
    rows.forEach((r) => items.push({ entity, label, id: r.id, title: r[titleKey], deletedAt: r.deleted_at }));

  push(
    'task',
    'مهمة',
    await all(
      db,
      `SELECT id, title, deleted_at FROM tasks WHERE deleted_at > ? AND (${mgr ? "kind != 'personal' OR " : ''}(kind = 'personal' AND assignee_id = ?))`,
      since,
      me.id,
    ),
  );
  push('goal', 'هدف', await all(db, 'SELECT id, title, deleted_at FROM goals WHERE deleted_at > ? AND user_id = ?', since, me.id));
  push('habit', 'عادة', await all(db, 'SELECT id, title, deleted_at FROM habits WHERE deleted_at > ? AND user_id = ?', since, me.id));
  push(
    'shared_expense',
    'مصروف مشترك',
    await all(db, `SELECT id, title, deleted_at FROM shared_expenses WHERE deleted_at > ? ${mgr ? '' : 'AND created_by = ?'}`, since, ...(mgr ? [] : [me.id])),
  );
  push(
    'debt',
    'دين',
    await all(
      db,
      `SELECT d.id, COALESCE(d.title, 'دين') AS title, d.deleted_at FROM debts d WHERE d.deleted_at > ? ${mgr ? '' : 'AND d.created_by = ?'}`,
      since,
      ...(mgr ? [] : [me.id]),
    ),
  );
  if (mgr) {
    push('chore', 'مهمة سكن', await all(db, 'SELECT id, name, deleted_at FROM chores WHERE deleted_at > ?', since), 'name');
    push('project', 'مشروع', await all(db, 'SELECT id, name, deleted_at FROM projects WHERE deleted_at > ?', since), 'name');
    push('event', 'حدث', await all(db, 'SELECT id, title, deleted_at FROM events WHERE deleted_at > ?', since));
    push('contribution_period', 'دورة مساهمات', await all(db, 'SELECT id, title, deleted_at FROM contribution_periods WHERE deleted_at > ?', since));
    push('user', 'عضو', await all(db, 'SELECT id, name, deleted_at FROM users WHERE deleted_at > ?', since), 'name');
  }
  items.sort((a, b) => b.deletedAt.localeCompare(a.deletedAt));
  return c.json({ items, days: TRASH_DAYS });
});

const RESTORE = {
  task: { table: 'tasks', check: (me, r) => (r.kind === 'personal' ? r.assignee_id === me.id : isManager(me)) },
  goal: { table: 'goals', check: (me, r) => r.user_id === me.id },
  habit: { table: 'habits', check: (me, r) => r.user_id === me.id },
  shared_expense: { table: 'shared_expenses', check: (me, r) => isManager(me) || r.created_by === me.id },
  debt: { table: 'debts', check: (me, r) => isManager(me) || r.created_by === me.id },
  chore: { table: 'chores', check: (me) => isManager(me) },
  project: { table: 'projects', check: (me) => isManager(me) },
  event: { table: 'events', check: (me) => isManager(me) },
  contribution_period: { table: 'contribution_periods', check: (me) => isManager(me) },
  user: { table: 'users', check: (me) => isManager(me) },
};

common.post('/trash/restore', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { entity: v.enum(Object.keys(RESTORE)), id: v.id() });
  const def = RESTORE[b.entity];
  const row = await first(c.env.DB, `SELECT * FROM ${def.table} WHERE id = ? AND deleted_at IS NOT NULL`, b.id);
  if (!row) throw notFound();
  if (!def.check(me, row)) throw forbidden();
  await run(c.env.DB, `UPDATE ${def.table} SET deleted_at = NULL WHERE id = ?`, b.id);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- reorder (▲▼ arrows / drag)
const REORDER = {
  members: { table: 'users', scope: (me) => (isManager(me) ? ['1 = 1', []] : null) },
  chores: { table: 'chores', scope: (me) => (isManager(me) ? ['1 = 1', []] : null) },
  projects: { table: 'projects', scope: (me) => (isManager(me) ? ['1 = 1', []] : null) },
  tasks: { table: 'tasks', scope: (me) => (isManager(me) ? ["(kind != 'personal' OR assignee_id = ?)", [me.id]] : ["kind = 'personal' AND assignee_id = ?", [me.id]]) },
  goals: { table: 'goals', scope: (me) => ['user_id = ?', [me.id]] },
  habits: { table: 'habits', scope: (me) => ['user_id = ?', [me.id]] },
};

common.post('/reorder', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), { entity: v.enum(Object.keys(REORDER)), ids: v.array(v.id(), { min: 1, max: 500 }) });
  const def = REORDER[b.entity];
  const scope = def.scope(me);
  if (!scope) throw forbidden();
  const ids = [...new Set(b.ids)];
  const rows = await all(c.env.DB, `SELECT id FROM ${def.table} WHERE id IN (${inList(ids)}) AND ${scope[0]}`, ...ids, ...scope[1]);
  if (rows.length !== ids.length) throw badRequest('لا يمكنك ترتيب بعض هذه العناصر');
  // Keep the relative positions of other rows: reuse the slots these rows already occupy.
  const current = await all(c.env.DB, `SELECT id, sort_order FROM ${def.table} WHERE id IN (${inList(ids)}) ORDER BY sort_order, id`, ...ids);
  const slots = current.map((r) => r.sort_order);
  for (let i = 1; i < slots.length; i += 1) if (slots[i] <= slots[i - 1]) slots[i] = slots[i - 1] + 1;
  await batch(
    c.env.DB,
    ids.map((id, i) => [`UPDATE ${def.table} SET sort_order = ? WHERE id = ?`, slots[i], id]),
  );
  return c.json({ ok: true });
});

common.post('/goals/:id/steps/reorder', async (c) => {
  const me = c.get('user');
  const goalId = parseId(c.req.param('id'));
  const g = await first(c.env.DB, 'SELECT id FROM goals WHERE id = ? AND user_id = ?', goalId, me.id);
  if (!g) throw notFound();
  const b = parse(await readJson(c), { ids: v.array(v.id(), { min: 1, max: 100 }) });
  await batch(c.env.DB, b.ids.map((id, i) => ['UPDATE goal_steps SET sort_order = ? WHERE id = ? AND goal_id = ?', i, id, goalId]));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- change history
const HISTORY = new Set(['user', 'chore', 'project', 'event', 'shared_expense', 'debt', 'distribution', 'contribution', 'contribution_period']);

common.get('/activity/:entity/:id', async (c) => {
  const me = c.get('user');
  const entity = c.req.param('entity');
  if (!HISTORY.has(entity)) throw notFound();
  const id = parseId(c.req.param('id'));
  if (!isManager(me)) {
    if (entity === 'debt') {
      const d = await first(c.env.DB, 'SELECT creditor_id, debtor_id FROM debts WHERE id = ?', id);
      if (!d || (d.creditor_id !== me.id && d.debtor_id !== me.id)) throw notFound();
    } else if (!['shared_expense', 'project', 'event', 'chore'].includes(entity)) throw forbidden();
  }
  const rows = await all(
    c.env.DB,
    'SELECT a.*, u.name AS actor_name FROM activity_log a LEFT JOIN users u ON u.id = a.actor_id WHERE a.entity = ? AND a.entity_id = ? ORDER BY a.id DESC LIMIT 50',
    entity,
    id,
  );
  return c.json({ history: camelAll(rows) });
});

export default common;
