import { Hono } from 'hono';
import { SPECIALTIES, adenDate } from '@camp/domain';
import { assertManager, hashPassword, isManager, publicUser, tempPassword } from '../lib/auth.js';
import { all, batch, camel, camelAll, first, logActivity, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, forbidden, notFound, parseId, readJson } from '../lib/http.js';
import { parse, v } from '../lib/validate.js';

const members = new Hono();
const COLORS = ['#243F35', '#56856A', '#B68A47', '#4F6D8A', '#8A5A6E', '#6E7F4F', '#A0644B', '#5B6B9A'];

export async function getMember(db, id, { includeArchived = true } = {}) {
  const u = await first(
    db,
    `SELECT * FROM users WHERE id = ? AND deleted_at IS NULL ${includeArchived ? '' : 'AND archived_at IS NULL'}`,
    id,
  );
  if (!u) throw notFound('العضو غير موجود');
  return u;
}

export async function activeMembers(db) {
  return all(db, 'SELECT * FROM users WHERE deleted_at IS NULL AND archived_at IS NULL ORDER BY sort_order, id');
}

const memberSchema = {
  name: v.string({ min: 2, max: 60 }),
  username: v.string({ min: 3, max: 32 }),
  role: v.enum(['manager', 'member'], { defaultValue: 'member' }),
  specialty: v.enum(Object.keys(SPECIALTIES), { optional: true }),
  phone: v.string({ max: 30, optional: true }),
  color: v.string({ max: 9, optional: true }),
};

members.get('/members', async (c) => {
  const me = c.get('user');
  const rows = await all(
    c.env.DB,
    `SELECT * FROM users WHERE deleted_at IS NULL ${isManager(me) ? '' : 'AND archived_at IS NULL'} ORDER BY sort_order, id`,
  );
  const slots = await all(c.env.DB, 'SELECT * FROM member_slots ORDER BY dow, start_time');
  const today = adenDate();
  const absences = await all(c.env.DB, 'SELECT * FROM absences WHERE deleted_at IS NULL AND end_date >= ? ORDER BY start_date', today);
  return c.json({
    members: rows.map((u) => ({
      ...publicUser(u),
      slots: camelAll(slots.filter((s) => s.user_id === u.id)),
      absences: camelAll(absences.filter((a) => a.user_id === u.id)),
    })),
    specialties: SPECIALTIES,
  });
});

members.post('/members', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const body = parse(await readJson(c), memberSchema);
  const username = body.username.toLowerCase();
  if (!/^[a-z0-9_.-]+$/.test(username)) throw badRequest('اسم المستخدم بالأحرف الإنجليزية والأرقام فقط', { username: 'اسم المستخدم بالأحرف الإنجليزية والأرقام فقط' });
  if (await first(c.env.DB, 'SELECT id FROM users WHERE username = ?', username)) {
    throw badRequest('اسم المستخدم مستخدم مسبقاً', { username: 'اسم المستخدم مستخدم مسبقاً' });
  }
  const count = await first(c.env.DB, 'SELECT COUNT(*) AS n, COALESCE(MAX(sort_order), 0) AS mx FROM users WHERE deleted_at IS NULL');
  const password = tempPassword();
  const now = nowIso();
  const r = await run(
    c.env.DB,
    `INSERT INTO users (username, name, role, specialty, phone, color, password_hash, must_change_password, sort_order, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)`,
    username,
    body.name,
    body.role,
    body.specialty,
    body.phone,
    body.color || COLORS[count.n % COLORS.length],
    await hashPassword(password),
    count.mx + 1,
    now,
    now,
  );
  await logActivity(c.env.DB, 'user', r.meta.last_row_id, me.id, 'created');
  const user = await first(c.env.DB, 'SELECT * FROM users WHERE id = ?', r.meta.last_row_id);
  return c.json({ member: publicUser(user), tempPassword: password }, 201);
});

members.patch('/members/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const id = parseId(c.req.param('id'));
  const target = await getMember(c.env.DB, id);
  const { username: _ignored, ...editable } = memberSchema;
  const body = parse(await readJson(c), editable, { partial: true });
  if (body.role === 'member' && target.role === 'manager') {
    const managers = await first(c.env.DB, "SELECT COUNT(*) AS n FROM users WHERE role = 'manager' AND deleted_at IS NULL AND archived_at IS NULL");
    if (managers.n <= 1) throw conflict('يجب أن يبقى مدير واحد على الأقل');
  }
  const fields = Object.entries(body).filter(([, val]) => val !== undefined);
  if (fields.length) {
    const cols = { name: 'name', role: 'role', specialty: 'specialty', phone: 'phone', color: 'color' };
    await run(
      c.env.DB,
      `UPDATE users SET ${fields.map(([k]) => `${cols[k]} = ?`).join(', ')}, updated_at = ? WHERE id = ?`,
      ...fields.map(([, val]) => val),
      nowIso(),
      id,
    );
    if (body.role && body.role !== target.role) {
      await run(c.env.DB, 'UPDATE users SET session_version = session_version + 1 WHERE id = ?', id);
    }
    await logActivity(c.env.DB, 'user', id, me.id, 'updated', body);
  }
  return c.json({ member: publicUser(await getMember(c.env.DB, id)) });
});

async function guardLastManager(db, target, me) {
  if (target.id === me.id) throw conflict('لا يمكنك تنفيذ هذا الإجراء على حسابك');
  if (target.role === 'manager') {
    const managers = await first(db, "SELECT COUNT(*) AS n FROM users WHERE role = 'manager' AND deleted_at IS NULL AND archived_at IS NULL");
    if (managers.n <= 1) throw conflict('يجب أن يبقى مدير واحد على الأقل');
  }
}

members.post('/members/:id/archive', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const target = await getMember(c.env.DB, parseId(c.req.param('id')));
  await guardLastManager(c.env.DB, target, me);
  await run(c.env.DB, 'UPDATE users SET archived_at = ?, session_version = session_version + 1, updated_at = ? WHERE id = ?', nowIso(), nowIso(), target.id);
  await logActivity(c.env.DB, 'user', target.id, me.id, 'archived');
  return c.json({ ok: true });
});

members.post('/members/:id/unarchive', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const target = await getMember(c.env.DB, parseId(c.req.param('id')));
  await run(c.env.DB, 'UPDATE users SET archived_at = NULL, updated_at = ? WHERE id = ?', nowIso(), target.id);
  await logActivity(c.env.DB, 'user', target.id, me.id, 'unarchived');
  return c.json({ ok: true });
});

members.delete('/members/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const target = await getMember(c.env.DB, parseId(c.req.param('id')));
  await guardLastManager(c.env.DB, target, me);
  await run(c.env.DB, 'UPDATE users SET deleted_at = ?, session_version = session_version + 1 WHERE id = ?', nowIso(), target.id);
  await logActivity(c.env.DB, 'user', target.id, me.id, 'deleted');
  return c.json({ ok: true });
});

members.post('/members/:id/reset-password', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const target = await getMember(c.env.DB, parseId(c.req.param('id')));
  if (target.id === me.id) throw conflict('غيّر كلمة مرورك من الإعدادات');
  const password = tempPassword();
  await run(
    c.env.DB,
    'UPDATE users SET password_hash = ?, must_change_password = 1, session_version = session_version + 1, updated_at = ? WHERE id = ?',
    await hashPassword(password),
    nowIso(),
    target.id,
  );
  await logActivity(c.env.DB, 'user', target.id, me.id, 'password_reset');
  return c.json({ tempPassword: password });
});

// Fixed weekly schedule (university / work). Manager or the member themself.
members.put('/members/:id/slots', async (c) => {
  const me = c.get('user');
  const id = parseId(c.req.param('id'));
  if (!isManager(me) && me.id !== id) throw forbidden();
  await getMember(c.env.DB, id);
  const body = parse(await readJson(c), {
    slots: v.array(
      v.object({
        dow: v.int({ min: 0, max: 6 }),
        startTime: v.time(),
        endTime: v.time(),
        kind: v.enum(['university', 'work', 'other'], { defaultValue: 'university' }),
        label: v.string({ max: 60, optional: true }),
      }),
      { max: 40 },
    ),
  });
  for (const s of body.slots) {
    if (s.endTime <= s.startTime) throw badRequest('وقت النهاية يجب أن يكون بعد البداية', { slots: 'وقت النهاية يجب أن يكون بعد البداية' });
  }
  await batch(c.env.DB, [
    ['DELETE FROM member_slots WHERE user_id = ?', id],
    ...body.slots.map((s) => [
      'INSERT INTO member_slots (user_id, dow, start_time, end_time, kind, label) VALUES (?, ?, ?, ?, ?, ?)',
      id,
      s.dow,
      s.startTime,
      s.endTime,
      s.kind || 'university',
      s.label,
    ]),
  ]);
  return c.json({ slots: camelAll(await all(c.env.DB, 'SELECT * FROM member_slots WHERE user_id = ? ORDER BY dow, start_time', id)) });
});

// Absences (member records own; manager anyone).
members.get('/absences', async (c) => {
  const rows = await all(
    c.env.DB,
    `SELECT a.*, u.name AS user_name FROM absences a JOIN users u ON u.id = a.user_id
     WHERE a.deleted_at IS NULL AND a.end_date >= ? ORDER BY a.start_date`,
    c.req.query('from') || adenDate(),
  );
  return c.json({ absences: camelAll(rows) });
});

members.post('/absences', async (c) => {
  const me = c.get('user');
  const body = parse(await readJson(c), {
    userId: v.id({ optional: true }),
    startDate: v.date(),
    endDate: v.date(),
    reason: v.string({ max: 120, optional: true }),
  });
  const userId = body.userId || me.id;
  if (userId !== me.id && !isManager(me)) throw forbidden();
  await getMember(c.env.DB, userId, { includeArchived: false });
  if (body.endDate < body.startDate) throw badRequest('تاريخ النهاية قبل البداية', { endDate: 'تاريخ النهاية قبل البداية' });
  const r = await run(
    c.env.DB,
    'INSERT INTO absences (user_id, start_date, end_date, reason, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    userId,
    body.startDate,
    body.endDate,
    body.reason,
    me.id,
    nowIso(),
  );
  return c.json({ absence: camel(await first(c.env.DB, 'SELECT * FROM absences WHERE id = ?', r.meta.last_row_id)) }, 201);
});

members.delete('/absences/:id', async (c) => {
  const me = c.get('user');
  const a = await first(c.env.DB, 'SELECT * FROM absences WHERE id = ? AND deleted_at IS NULL', parseId(c.req.param('id')));
  if (!a) throw notFound();
  if (a.user_id !== me.id && !isManager(me)) throw forbidden();
  await run(c.env.DB, 'UPDATE absences SET deleted_at = ? WHERE id = ?', nowIso(), a.id);
  return c.json({ ok: true });
});

export default members;
