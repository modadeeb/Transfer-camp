// Projects, events/meetings and swap requests.
import { Hono } from 'hono';
import { formatDate } from '@camp/domain';
import { assertManager, isManager } from '../lib/auth.js';
import { all, camel, camelAll, first, inList, logActivity, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, forbidden, notFound, parseId, readJson } from '../lib/http.js';
import { fromRequest, notify } from '../lib/notify.js';
import { managerIds, taskLink } from '../lib/tasks.js';
import { parse, v } from '../lib/validate.js';

const work = new Hono();

// ---------------------------------------------------------------- projects
const projectSchema = {
  name: v.string({ min: 2, max: 80 }),
  client: v.string({ max: 80, optional: true }),
  description: v.text({ max: 2000 }),
  deadline: v.date({ optional: true }),
  status: v.enum(['active', 'on_hold', 'closed'], { defaultValue: 'active' }),
};

const PROJECT_SELECT = `
  SELECT p.*,
    (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.deleted_at IS NULL AND t.archived_at IS NULL) AS task_count,
    (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.deleted_at IS NULL AND t.archived_at IS NULL AND t.status = 'approved') AS done_count
  FROM projects p`;

async function loadProject(db, id, { includeDeleted = false } = {}) {
  const row = await first(db, `${PROJECT_SELECT} WHERE p.id = ? ${includeDeleted ? '' : 'AND p.deleted_at IS NULL'}`, id);
  if (!row) throw notFound('المشروع غير موجود');
  return row;
}

work.get('/projects', async (c) => {
  const archived = c.req.query('archived') === '1';
  const rows = await all(
    c.env.DB,
    `${PROJECT_SELECT} WHERE p.deleted_at IS NULL AND p.archived_at IS ${archived ? 'NOT NULL' : 'NULL'} ORDER BY p.status = 'closed', p.sort_order, p.id`,
  );
  return c.json({ projects: camelAll(rows) });
});

work.post('/projects', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const b = parse(await readJson(c), projectSchema);
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM projects');
  const now = nowIso();
  const r = await run(
    c.env.DB,
    'INSERT INTO projects (name, client, description, deadline, status, sort_order, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    b.name,
    b.client,
    b.description,
    b.deadline,
    b.status,
    mx.mx + 1,
    me.id,
    now,
    now,
  );
  await logActivity(c.env.DB, 'project', r.meta.last_row_id, me.id, 'created');
  return c.json({ project: camel(await loadProject(c.env.DB, r.meta.last_row_id)) }, 201);
});

work.patch('/projects/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadProject(c.env.DB, parseId(c.req.param('id')));
  const b = parse(await readJson(c), projectSchema, { partial: true });
  const cols = { name: 'name', client: 'client', description: 'description', deadline: 'deadline', status: 'status' };
  const entries = Object.entries(b).filter(([, val]) => val !== undefined);
  if (entries.length) {
    await run(
      c.env.DB,
      `UPDATE projects SET ${entries.map(([k]) => `${cols[k]} = ?`).join(', ')}, updated_at = ? WHERE id = ?`,
      ...entries.map(([, val]) => val),
      nowIso(),
      row.id,
    );
    await logActivity(c.env.DB, 'project', row.id, me.id, 'updated', b);
  }
  return c.json({ project: camel(await loadProject(c.env.DB, row.id)) });
});

work.post('/projects/:id/copy', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadProject(c.env.DB, parseId(c.req.param('id')));
  const mx = await first(c.env.DB, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM projects');
  const now = nowIso();
  const r = await run(
    c.env.DB,
    "INSERT INTO projects (name, client, description, deadline, status, sort_order, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?)",
    `${row.name} (نسخة)`,
    row.client,
    row.description,
    row.deadline,
    mx.mx + 1,
    me.id,
    now,
    now,
  );
  return c.json({ project: camel(await loadProject(c.env.DB, r.meta.last_row_id)) }, 201);
});

for (const [path, column, value] of [
  ['archive', 'archived_at', true],
  ['unarchive', 'archived_at', false],
  ['restore', 'deleted_at', false],
]) {
  work.post(`/projects/:id/${path}`, async (c) => {
    const me = c.get('user');
    assertManager(me);
    const row = await loadProject(c.env.DB, parseId(c.req.param('id')), { includeDeleted: path === 'restore' });
    await run(c.env.DB, `UPDATE projects SET ${column} = ?, updated_at = ? WHERE id = ?`, value ? nowIso() : null, nowIso(), row.id);
    await logActivity(c.env.DB, 'project', row.id, me.id, path);
    return c.json({ project: camel(await loadProject(c.env.DB, row.id)) });
  });
}

work.delete('/projects/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadProject(c.env.DB, parseId(c.req.param('id')));
  await run(c.env.DB, 'UPDATE projects SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
  await logActivity(c.env.DB, 'project', row.id, me.id, 'deleted');
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- events
const eventSchema = {
  title: v.string({ min: 2, max: 100 }),
  kind: v.enum(['meeting', 'deadline', 'other'], { defaultValue: 'meeting' }),
  date: v.date(),
  startTime: v.time({ optional: true }),
  endTime: v.time({ optional: true }),
  everyone: v.bool({ defaultValue: true }),
  memberIds: v.array(v.id(), { max: 20, optional: true }),
  notes: v.text({ max: 1000 }),
};

async function loadEvent(db, id, { includeDeleted = false } = {}) {
  const row = await first(db, `SELECT * FROM events WHERE id = ? ${includeDeleted ? '' : 'AND deleted_at IS NULL'}`, id);
  if (!row) throw notFound('الحدث غير موجود');
  return row;
}

work.get('/events', async (c) => {
  const { from, to } = c.req.query();
  const where = ['deleted_at IS NULL'];
  const params = [];
  if (from) {
    where.push('date >= ?');
    params.push(from);
  }
  if (to) {
    where.push('date <= ?');
    params.push(to);
  }
  const rows = await all(c.env.DB, `SELECT * FROM events WHERE ${where.join(' AND ')} ORDER BY date, start_time IS NULL, start_time, id`, ...params);
  return c.json({ events: camelAll(rows) });
});

async function saveEvent(c, body, existing) {
  const me = c.get('user');
  if (body.startTime && body.endTime && body.endTime <= body.startTime) {
    throw badRequest('وقت النهاية يجب أن يكون بعد البداية', { endTime: 'وقت النهاية يجب أن يكون بعد البداية' });
  }
  const memberIds = body.everyone ? [] : body.memberIds || [];
  if (!body.everyone && !memberIds.length) throw badRequest('اختر الحاضرين', { memberIds: 'اختر الحاضرين' });
  const now = nowIso();
  let id = existing?.id;
  if (existing) {
    await run(
      c.env.DB,
      'UPDATE events SET title = ?, kind = ?, date = ?, start_time = ?, end_time = ?, everyone = ?, member_ids = ?, notes = ?, updated_at = ? WHERE id = ?',
      body.title,
      body.kind,
      body.date,
      body.startTime,
      body.endTime,
      body.everyone,
      JSON.stringify(memberIds),
      body.notes,
      now,
      id,
    );
  } else {
    const r = await run(
      c.env.DB,
      'INSERT INTO events (title, kind, date, start_time, end_time, everyone, member_ids, notes, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      body.title,
      body.kind,
      body.date,
      body.startTime,
      body.endTime,
      body.everyone,
      JSON.stringify(memberIds),
      body.notes,
      me.id,
      now,
      now,
    );
    id = r.meta.last_row_id;
  }
  await logActivity(c.env.DB, 'event', id, me.id, existing ? 'updated' : 'created');
  return loadEvent(c.env.DB, id);
}

work.post('/events', async (c) => {
  assertManager(c.get('user'));
  const b = parse(await readJson(c), eventSchema);
  return c.json({ event: camel(await saveEvent(c, b)) }, 201);
});

work.patch('/events/:id', async (c) => {
  assertManager(c.get('user'));
  const row = await loadEvent(c.env.DB, parseId(c.req.param('id')));
  const current = camel(row);
  const b = parse(await readJson(c), eventSchema, { partial: true });
  const merged = { ...current, ...Object.fromEntries(Object.entries(b).filter(([, val]) => val !== undefined)) };
  return c.json({ event: camel(await saveEvent(c, merged, row)) });
});

work.post('/events/:id/copy', async (c) => {
  assertManager(c.get('user'));
  const row = camel(await loadEvent(c.env.DB, parseId(c.req.param('id'))));
  return c.json({ event: camel(await saveEvent(c, row)) }, 201);
});

work.post('/events/:id/restore', async (c) => {
  assertManager(c.get('user'));
  const row = await loadEvent(c.env.DB, parseId(c.req.param('id')), { includeDeleted: true });
  await run(c.env.DB, 'UPDATE events SET deleted_at = NULL WHERE id = ?', row.id);
  return c.json({ event: camel(await loadEvent(c.env.DB, row.id)) });
});

work.delete('/events/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadEvent(c.env.DB, parseId(c.req.param('id')));
  await run(c.env.DB, 'UPDATE events SET deleted_at = ? WHERE id = ?', nowIso(), row.id);
  await logActivity(c.env.DB, 'event', row.id, me.id, 'deleted');
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- swap requests
const SWAP_SELECT = `
  SELECT s.*, f.name AS from_name, tu.name AS to_name,
    t.title AS task_title, t.due_date AS task_due_date, t.kind AS task_kind, t.size AS task_size,
    ct.title AS counter_title, ct.due_date AS counter_due_date, ct.size AS counter_size
  FROM swap_requests s
  JOIN users f ON f.id = s.from_user_id JOIN users tu ON tu.id = s.to_user_id
  JOIN tasks t ON t.id = s.task_id LEFT JOIN tasks ct ON ct.id = s.counter_task_id`;

work.get('/swaps', async (c) => {
  const me = c.get('user');
  const all_ = c.req.query('all') === '1' && isManager(me);
  const rows = await all(
    c.env.DB,
    `${SWAP_SELECT} WHERE s.deleted_at IS NULL ${all_ ? '' : 'AND (s.from_user_id = ? OR s.to_user_id = ?)'} ORDER BY s.status = 'pending' DESC, s.id DESC LIMIT 100`,
    ...(all_ ? [] : [me.id, me.id]),
  );
  return c.json({ swaps: camelAll(rows) });
});

work.post('/swaps', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const b = parse(await readJson(c), {
    taskId: v.id(),
    toUserId: v.id(),
    counterTaskId: v.id({ optional: true }),
    note: v.string({ max: 300, optional: true }),
  });
  const task = await first(db, 'SELECT * FROM tasks WHERE id = ? AND deleted_at IS NULL AND archived_at IS NULL', b.taskId);
  if (!task || task.kind === 'personal') throw notFound('المهمة غير موجودة');
  if (task.assignee_id !== me.id) throw forbidden('يمكنك طلب تبديل مهامك فقط');
  if (task.status === 'approved') throw conflict('لا يمكن تبديل مهمة منجزة');
  if (b.toUserId === me.id) throw badRequest('اختر زميلاً آخر');
  const to = await first(db, 'SELECT id, name FROM users WHERE id = ? AND deleted_at IS NULL AND archived_at IS NULL', b.toUserId);
  if (!to) throw badRequest('الزميل غير موجود');
  if (b.counterTaskId) {
    const ct = await first(db, 'SELECT * FROM tasks WHERE id = ? AND deleted_at IS NULL AND archived_at IS NULL', b.counterTaskId);
    if (!ct || ct.assignee_id !== b.toUserId || ct.kind !== task.kind || ct.status === 'approved') {
      throw badRequest('مهمة المقابل غير صالحة', { counterTaskId: 'مهمة المقابل غير صالحة' });
    }
  }
  const pending = await first(db, "SELECT id FROM swap_requests WHERE task_id = ? AND status = 'pending' AND deleted_at IS NULL", task.id);
  if (pending) throw conflict('يوجد طلب تبديل معلّق لهذه المهمة');
  const r = await run(
    db,
    'INSERT INTO swap_requests (task_id, counter_task_id, from_user_id, to_user_id, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    task.id,
    b.counterTaskId,
    me.id,
    b.toUserId,
    b.note,
    nowIso(),
  );
  await notify(fromRequest(c), [b.toUserId], {
    type: 'swap_request',
    title: 'طلب تبديل مهمة',
    body: `${me.name} يطلب منك «${task.title}»${task.due_date ? ` (${formatDate(task.due_date, { weekday: true })})` : ''}`,
    link: '/housing?tab=swaps',
  });
  return c.json({ swap: camel(await first(db, `${SWAP_SELECT} WHERE s.id = ?`, r.meta.last_row_id)) }, 201);
});

async function loadSwap(db, id) {
  const s = await first(db, `${SWAP_SELECT} WHERE s.id = ? AND s.deleted_at IS NULL`, id);
  if (!s) throw notFound('الطلب غير موجود');
  return s;
}

work.post('/swaps/:id/:decision', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const decision = c.req.param('decision');
  if (!['accept', 'reject', 'cancel'].includes(decision)) throw notFound();
  const s = await loadSwap(db, parseId(c.req.param('id')));
  if (s.status !== 'pending') throw conflict('تم الرد على هذا الطلب مسبقاً');
  if (decision === 'cancel' && s.from_user_id !== me.id && !isManager(me)) throw forbidden();
  if (decision !== 'cancel' && s.to_user_id !== me.id) throw forbidden('هذا الطلب ليس موجهاً إليك');

  const status = { accept: 'accepted', reject: 'rejected', cancel: 'cancelled' }[decision];
  if (decision === 'accept') {
    const ids = [s.task_id, s.counter_task_id].filter(Boolean);
    const current = await all(db, `SELECT id, assignee_id, status, deleted_at FROM tasks WHERE id IN (${inList(ids)})`, ...ids);
    const t = current.find((x) => x.id === s.task_id);
    if (!t || t.deleted_at || t.assignee_id !== s.from_user_id || t.status === 'approved') throw conflict('تغيّرت المهمة ولم يعد التبديل ممكناً');
    if (s.counter_task_id) {
      const ct = current.find((x) => x.id === s.counter_task_id);
      if (!ct || ct.deleted_at || ct.assignee_id !== s.to_user_id || ct.status === 'approved') throw conflict('تغيّرت مهمة المقابل ولم يعد التبديل ممكناً');
    }
  }
  const lock = await run(db, "UPDATE swap_requests SET status = ?, responded_at = ? WHERE id = ? AND status = 'pending'", status, nowIso(), s.id);
  if (!lock.meta.changes) throw conflict('تم الرد على هذا الطلب مسبقاً');
  if (decision === 'accept') {
    await run(db, 'UPDATE tasks SET assignee_id = ?, updated_at = ? WHERE id = ?', s.to_user_id, nowIso(), s.task_id);
    await logActivity(db, 'task', s.task_id, me.id, 'swapped', { from: s.from_user_id, to: s.to_user_id });
    if (s.counter_task_id) {
      await run(db, 'UPDATE tasks SET assignee_id = ?, updated_at = ? WHERE id = ?', s.from_user_id, nowIso(), s.counter_task_id);
      await logActivity(db, 'task', s.counter_task_id, me.id, 'swapped', { from: s.to_user_id, to: s.from_user_id });
    }
  }
  const ctx = fromRequest(c);
  if (decision === 'cancel') {
    if (me.id !== s.to_user_id) {
      await notify(ctx, [s.to_user_id], { type: 'swap_response', title: 'أُلغي طلب تبديل', body: s.task_title, link: '/housing?tab=swaps' });
    }
  } else {
    await notify(ctx, [s.from_user_id], {
      type: 'swap_response',
      title: decision === 'accept' ? 'قُبل طلب التبديل ✓' : 'رُفض طلب التبديل',
      body: `${s.to_name}: «${s.task_title}»`,
      link: decision === 'accept' ? taskLink(s.counter_task_id || s.task_id) : '/housing?tab=swaps',
    });
    if (decision === 'accept') {
      const managers = (await managerIds(db)).filter((id) => ![s.from_user_id, s.to_user_id].includes(id));
      await notify(ctx, managers, {
        type: 'swap_response',
        title: 'تبديل مهمة',
        body: `«${s.task_title}» انتقلت من ${s.from_name} إلى ${s.to_name}`,
        link: taskLink(s.task_id),
      });
    }
  }
  return c.json({ swap: camel(await loadSwap(db, s.id)) });
});

export default work;
