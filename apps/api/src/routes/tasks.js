import { Hono } from 'hono';
import {
  PRIORITIES,
  RECURRENCES,
  SPECIALTIES,
  STATUS_LABELS,
  TransitionError,
  adenDate,
  adenTime,
  addDays,
  nextStatus,
  suggestAssignees,
  weekStartOf,
} from '@camp/domain';
import { isManager } from '../lib/auth.js';
import { all, camelAll, first, inList, logActivity, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, forbidden, parseId, readJson } from '../lib/http.js';
import { fromRequest, notify } from '../lib/notify.js';
import {
  TASK_SELECT,
  assertCanEdit,
  canEdit,
  insertTask,
  leastLoadedForHouse,
  loadTask,
  managerIds,
  normalizeChecklist,
  notifyAssigned,
  serializeTask,
  spawnNextOccurrence,
  taskLink,
} from '../lib/tasks.js';
import { parse, v } from '../lib/validate.js';
import { activeMembers } from './members.js';

const tasks = new Hono();

const checklistItem = v.object({ id: v.string({ max: 20, optional: true }), text: v.string({ max: 200 }), done: v.bool({ optional: true }) });
const attachment = v.object({ url: v.url(), label: v.string({ max: 80, optional: true }) });

const taskSchema = {
  kind: v.enum(['house', 'company', 'personal']),
  title: v.string({ min: 2, max: 140 }),
  details: v.text({ max: 4000 }),
  assigneeIds: v.array(v.id(), { max: 8, optional: true }),
  autoAssign: v.bool({ defaultValue: false }),
  projectId: v.id({ optional: true }),
  specialty: v.enum(Object.keys(SPECIALTIES), { optional: true }),
  dueDate: v.date({ optional: true }),
  dueTime: v.time({ optional: true }),
  priority: v.enum(PRIORITIES, { defaultValue: 'normal' }),
  size: v.int({ min: 1, max: 200, defaultValue: 1 }),
  recurrence: v.enum(RECURRENCES, { defaultValue: 'none' }),
  needsApproval: v.bool({ optional: true }),
  checklist: v.array(checklistItem, { max: 50, optional: true }),
  attachments: v.array(attachment, { max: 10, optional: true }),
};

function checkSize(kind, size) {
  if (kind === 'house' && size > 5) throw badRequest('نقاط مهمة السكن من 1 إلى 5', { size: 'نقاط مهمة السكن من 1 إلى 5' });
}

async function assertProject(db, projectId) {
  if (!projectId) return;
  const p = await first(db, 'SELECT id FROM projects WHERE id = ? AND deleted_at IS NULL', projectId);
  if (!p) throw badRequest('المشروع غير موجود', { projectId: 'المشروع غير موجود' });
}

async function assertMembers(db, ids) {
  if (!ids.length) return;
  const rows = await all(db, `SELECT id FROM users WHERE id IN (${inList(ids)}) AND deleted_at IS NULL AND archived_at IS NULL`, ...ids);
  if (rows.length !== new Set(ids).size) throw badRequest('أحد الأعضاء غير موجود', { assigneeIds: 'أحد الأعضاء غير موجود' });
}

tasks.get('/tasks', async (c) => {
  const me = c.get('user');
  const q = c.req.query();
  const where = ['(t.kind != ? OR t.assignee_id = ?)'];
  const params = ['personal', me.id];
  where.push(q.archived === '1' ? 't.archived_at IS NOT NULL' : 't.archived_at IS NULL');
  where.push('t.deleted_at IS NULL');
  if (q.kind) {
    const kinds = q.kind.split(',').filter((k) => ['house', 'company', 'personal'].includes(k));
    if (kinds.length) {
      where.push(`t.kind IN (${inList(kinds)})`);
      params.push(...kinds);
    }
  }
  if (q.mine === '1') {
    where.push('t.assignee_id = ?');
    params.push(me.id);
  } else if (q.assigneeId) {
    where.push('t.assignee_id = ?');
    params.push(Number(q.assigneeId));
  }
  if (q.status) {
    const st = q.status.split(',');
    where.push(`t.status IN (${inList(st)})`);
    params.push(...st);
  }
  if (q.projectId) {
    where.push('t.project_id = ?');
    params.push(Number(q.projectId));
  }
  if (q.from) {
    where.push('t.due_date >= ?');
    params.push(q.from);
  }
  if (q.to) {
    where.push('t.due_date <= ?');
    params.push(q.to);
  }
  if (q.priority) {
    where.push('t.priority = ?');
    params.push(q.priority);
  }
  if (q.q) {
    where.push('(t.title LIKE ? OR t.details LIKE ?)');
    params.push(`%${q.q}%`, `%${q.q}%`);
  }
  if (q.overdue === '1') {
    where.push("t.status != 'approved' AND t.due_date IS NOT NULL AND (t.due_date < ? OR (t.due_date = ? AND t.due_time IS NOT NULL AND t.due_time < ?))");
    const today = adenDate();
    params.push(today, today, adenTime());
  }
  const limit = Math.min(Number(q.limit) || 500, 1000);
  const rows = await all(
    c.env.DB,
    `${TASK_SELECT} WHERE ${where.join(' AND ')} ORDER BY t.sort_order, t.due_date IS NULL, t.due_date, t.due_time, t.id LIMIT ${limit}`,
    ...params,
  );
  return c.json({ tasks: rows.map(serializeTask) });
});

tasks.get('/tasks/suggest', async (c) => {
  const me = c.get('user');
  if (!isManager(me)) throw forbidden();
  const members = (await activeMembers(c.env.DB)).map((m) => ({ id: m.id, specialty: m.specialty, sortOrder: m.sort_order }));
  const kind = c.req.query('kind') || 'company';
  if (kind === 'house') {
    const date = c.req.query('date') || adenDate();
    const ws = weekStartOf(date);
    const id = await leastLoadedForHouse(c.env.DB, members.map((m) => m.id), ws, addDays(ws, 6));
    return c.json({ suggestions: id ? [{ userId: id }] : [] });
  }
  const open = camelAll(await all(c.env.DB, "SELECT assignee_id, size, status, kind, deleted_at, archived_at FROM tasks WHERE kind = 'company'"));
  return c.json({ suggestions: suggestAssignees({ members, tasks: open, specialty: c.req.query('specialty') || null }) });
});

tasks.post('/tasks', async (c) => {
  const me = c.get('user');
  const body = parse(await readJson(c), taskSchema);
  const db = c.env.DB;
  checkSize(body.kind, body.size);
  let assignees;
  if (body.kind === 'personal') {
    assignees = [me.id];
  } else {
    if (!isManager(me)) throw forbidden('إضافة المهام المشتركة للمدير فقط');
    await assertProject(db, body.projectId);
    assignees = [...new Set(body.assigneeIds || [])];
    await assertMembers(db, assignees);
    if (!assignees.length && body.autoAssign) {
      const members = (await activeMembers(db)).map((m) => ({ id: m.id, specialty: m.specialty, sortOrder: m.sort_order }));
      if (body.kind === 'house') {
        const ws = weekStartOf(body.dueDate || adenDate());
        const id = await leastLoadedForHouse(db, members.map((m) => m.id), ws, addDays(ws, 6));
        if (id) assignees = [id];
      } else {
        const open = camelAll(await all(db, "SELECT assignee_id, size, status, kind, deleted_at, archived_at FROM tasks WHERE kind = 'company'"));
        const s = suggestAssignees({ members, tasks: open, specialty: body.specialty });
        if (s[0]) assignees = [s[0].userId];
      }
    }
  }
  if (!assignees.length) assignees = [null];
  const groupId = assignees.length > 1 ? crypto.randomUUID() : null;
  const ids = [];
  for (const assigneeId of assignees) {
    const id = await insertTask(db, {
      kind: body.kind,
      title: body.title,
      details: body.details,
      assignee_id: assigneeId,
      project_id: body.kind === 'company' ? body.projectId : null,
      specialty: body.kind === 'company' ? body.specialty : null,
      due_date: body.dueDate,
      due_time: body.dueTime,
      priority: body.priority,
      size: body.size,
      recurrence: body.recurrence,
      needs_approval: body.needsApproval === null ? undefined : body.needsApproval ? 1 : 0,
      checklist: body.checklist || [],
      attachments: body.attachments || [],
      group_id: groupId,
      created_by: me.id,
    });
    ids.push(id);
  }
  const rows = await all(db, `${TASK_SELECT} WHERE t.id IN (${inList(ids)})`, ...ids);
  const ctx = fromRequest(c);
  for (const row of rows) await notifyAssigned(ctx, row, me.id);
  return c.json({ tasks: rows.map(serializeTask) }, 201);
});

tasks.get('/tasks/:id', async (c) => {
  const me = c.get('user');
  const row = await loadTask(c.env.DB, parseId(c.req.param('id')), me);
  const history = await all(
    c.env.DB,
    `SELECT a.*, u.name AS actor_name FROM activity_log a LEFT JOIN users u ON u.id = a.actor_id
     WHERE a.entity = 'task' AND a.entity_id = ? ORDER BY a.id DESC LIMIT 50`,
    row.id,
  );
  const swaps = await all(
    c.env.DB,
    `SELECT s.*, f.name AS from_name, t.name AS to_name FROM swap_requests s
     JOIN users f ON f.id = s.from_user_id JOIN users t ON t.id = s.to_user_id
     WHERE (s.task_id = ? OR s.counter_task_id = ?) AND s.deleted_at IS NULL ORDER BY s.id DESC`,
    row.id,
    row.id,
  );
  return c.json({
    task: serializeTask(row),
    history: camelAll(history),
    swaps: camelAll(swaps),
    canEdit: canEdit(me, row),
  });
});

tasks.patch('/tasks/:id', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const row = await loadTask(db, parseId(c.req.param('id')), me);
  assertCanEdit(me, row);
  const { kind: _k, assigneeIds: _a, autoAssign: _aa, ...editable } = taskSchema;
  const body = parse(await readJson(c), { ...editable, assigneeId: v.id({ optional: true }) }, { partial: true });
  if (body.size !== undefined) checkSize(row.kind, body.size);
  if (body.projectId) await assertProject(db, body.projectId);
  if (row.kind === 'personal') delete body.assigneeId;
  if (body.assigneeId) await assertMembers(db, [body.assigneeId]);

  const map = {
    title: 'title',
    details: 'details',
    projectId: 'project_id',
    specialty: 'specialty',
    dueDate: 'due_date',
    dueTime: 'due_time',
    priority: 'priority',
    size: 'size',
    recurrence: 'recurrence',
    needsApproval: 'needs_approval',
    assigneeId: 'assignee_id',
  };
  const sets = [];
  const params = [];
  for (const [k, col] of Object.entries(map)) {
    if (body[k] === undefined) continue;
    sets.push(`${col} = ?`);
    params.push(k === 'needsApproval' ? (body[k] ? 1 : 0) : body[k]);
  }
  if (body.checklist !== undefined) {
    sets.push('checklist = ?');
    params.push(JSON.stringify(normalizeChecklist(body.checklist || [])));
  }
  if (body.attachments !== undefined) {
    sets.push('attachments = ?');
    params.push(JSON.stringify(body.attachments || []));
  }
  if (body.dueDate !== undefined || body.dueTime !== undefined) {
    sets.push('reminded_at = NULL', 'overdue_notified_at = NULL');
  }
  if (!sets.length) return c.json({ task: serializeTask(row) });
  await run(db, `UPDATE tasks SET ${sets.join(', ')}, updated_at = ? WHERE id = ?`, ...params, nowIso(), row.id);
  await logActivity(db, 'task', row.id, me.id, 'updated', body);

  const fresh = await loadTask(db, row.id, me);
  const ctx = fromRequest(c);
  if (row.kind !== 'personal') {
    if (body.assigneeId && body.assigneeId !== row.assignee_id) {
      await notifyAssigned(ctx, fresh, me.id);
      if (row.assignee_id && row.assignee_id !== me.id) {
        await notify(ctx, [row.assignee_id], {
          type: 'task_deleted',
          title: 'أُعيد إسناد مهمة',
          body: `«${row.title}» صارت مسندة لزميل آخر`,
          link: '/',
        });
      }
    } else if (fresh.assignee_id && fresh.assignee_id !== me.id && ['dueDate', 'dueTime', 'details', 'title', 'priority', 'checklist'].some((k) => body[k] !== undefined)) {
      await notify(ctx, [fresh.assignee_id], {
        type: 'task_updated',
        title: 'تعديل على مهمتك',
        body: fresh.title,
        link: taskLink(fresh.id),
      });
    }
  }
  return c.json({ task: serializeTask(fresh) });
});

tasks.post('/tasks/:id/checklist', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const row = await loadTask(db, parseId(c.req.param('id')), me);
  if (row.assignee_id !== me.id && !canEdit(me, row)) throw forbidden();
  const body = parse(await readJson(c), { itemId: v.string({ max: 20 }), done: v.bool() });
  const list = JSON.parse(row.checklist || '[]');
  const item = list.find((i) => i.id === body.itemId);
  if (!item) throw badRequest('البند غير موجود');
  item.done = body.done;
  await run(db, 'UPDATE tasks SET checklist = ?, updated_at = ? WHERE id = ?', JSON.stringify(list), nowIso(), row.id);
  return c.json({ task: serializeTask(await loadTask(db, row.id, me)) });
});

tasks.post('/tasks/:id/action', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const row = await loadTask(db, parseId(c.req.param('id')), me);
  if (row.archived_at) throw conflict('المهمة مؤرشفة');
  const body = parse(await readJson(c), {
    action: v.enum(['start', 'submit', 'approve', 'return', 'undo', 'set']),
    note: v.text({ max: 1000 }),
    url: v.url({ optional: true }),
    status: v.enum(['pending', 'in_progress', 'submitted', 'approved', 'returned'], { optional: true }),
  });
  const manager = row.kind === 'personal' ? row.assignee_id === me.id : isManager(me);
  let status;
  try {
    status = nextStatus(
      { status: row.status, needsApproval: row.kind === 'personal' ? false : row.needs_approval },
      body.action,
      { isManager: manager, isAssignee: row.assignee_id === me.id, status: body.status },
    );
  } catch (e) {
    if (e instanceof TransitionError) throw conflict(e.message);
    throw e;
  }
  if (body.action === 'return' && !body.note) throw badRequest('اكتب سبب الإعادة', { note: 'اكتب سبب الإعادة' });

  const now = nowIso();
  const sets = ['status = ?', 'updated_at = ?'];
  const params = [status, now];
  if (status === 'in_progress' && !row.started_at) {
    sets.push('started_at = ?');
    params.push(now);
  }
  if (body.action === 'submit') {
    sets.push('submitted_at = ?', 'completion_note = ?', 'completion_url = ?');
    params.push(now, body.note, body.url);
  }
  if (status === 'approved') {
    sets.push('approved_at = ?', 'approved_by = ?');
    params.push(now, me.id);
  } else {
    sets.push('approved_at = NULL', 'approved_by = NULL');
  }
  if (body.action === 'return') {
    sets.push('return_note = ?');
    params.push(body.note);
  }
  await run(db, `UPDATE tasks SET ${sets.join(', ')} WHERE id = ?`, ...params, row.id);
  await logActivity(db, 'task', row.id, me.id, body.action, { status, note: body.note || undefined });

  const ctx = fromRequest(c);
  let nextId = null;
  if (status === 'approved' && row.status !== 'approved') nextId = await spawnNextOccurrence(db, { ...row, status });
  if (row.kind !== 'personal') {
    if (status === 'submitted') {
      await notify(ctx, await managerIds(db), {
        type: 'task_submitted',
        title: 'مهمة بانتظار اعتمادك',
        body: `${row.assignee_name || ''}: ${row.title}`,
        link: taskLink(row.id),
      });
    } else if (body.action === 'approve' && row.assignee_id !== me.id) {
      await notify(ctx, [row.assignee_id], { type: 'task_approved', title: 'اعتُمدت مهمتك ✓', body: row.title, link: taskLink(row.id) });
    } else if (body.action === 'return' && row.assignee_id !== me.id) {
      await notify(ctx, [row.assignee_id], {
        type: 'task_returned',
        title: 'أُعيدت مهمة إليك',
        body: `${row.title} — ${body.note}`,
        link: taskLink(row.id),
      });
    } else if (body.action === 'set' && row.assignee_id && row.assignee_id !== me.id) {
      await notify(ctx, [row.assignee_id], {
        type: 'task_updated',
        title: 'تغيّرت حالة مهمتك',
        body: `${row.title}: ${STATUS_LABELS[status]}`,
        link: taskLink(row.id),
      });
    }
  }
  if (nextId) {
    const next = await first(db, `${TASK_SELECT} WHERE t.id = ?`, nextId);
    await notifyAssigned(ctx, next, me.id);
  }
  return c.json({ task: serializeTask(await loadTask(db, row.id, me)), nextTaskId: nextId });
});

async function softDelete(c, row, me) {
  const db = c.env.DB;
  if (row.kind !== 'personal' && row.status === 'approved') {
    await run(db, 'UPDATE tasks SET archived_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
    await logActivity(db, 'task', row.id, me.id, 'archived');
    return 'archived';
  }
  await run(db, 'UPDATE tasks SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
  await logActivity(db, 'task', row.id, me.id, 'deleted');
  if (row.kind !== 'personal' && row.assignee_id && row.assignee_id !== me.id) {
    await notify(fromRequest(c), [row.assignee_id], { type: 'task_deleted', title: 'حُذفت مهمة', body: row.title, link: '/' });
  }
  return 'deleted';
}

tasks.delete('/tasks/:id', async (c) => {
  const me = c.get('user');
  const row = await loadTask(c.env.DB, parseId(c.req.param('id')), me);
  assertCanEdit(me, row);
  const result = await softDelete(c, row, me);
  return c.json({ result });
});

tasks.post('/tasks/:id/restore', async (c) => {
  const me = c.get('user');
  const row = await loadTask(c.env.DB, parseId(c.req.param('id')), me, { includeDeleted: true });
  assertCanEdit(me, row);
  await run(c.env.DB, 'UPDATE tasks SET deleted_at = NULL, archived_at = NULL, updated_at = ? WHERE id = ?', nowIso(), row.id);
  await logActivity(c.env.DB, 'task', row.id, me.id, 'restored');
  return c.json({ task: serializeTask(await loadTask(c.env.DB, row.id, me)) });
});

for (const [path, value, action] of [
  ['archive', 'CURRENT', 'archived'],
  ['unarchive', null, 'unarchived'],
]) {
  tasks.post(`/tasks/:id/${path}`, async (c) => {
    const me = c.get('user');
    const row = await loadTask(c.env.DB, parseId(c.req.param('id')), me);
    assertCanEdit(me, row);
    await run(c.env.DB, 'UPDATE tasks SET archived_at = ?, updated_at = ? WHERE id = ?', value ? nowIso() : null, nowIso(), row.id);
    await logActivity(c.env.DB, 'task', row.id, me.id, action);
    return c.json({ task: serializeTask(await loadTask(c.env.DB, row.id, me)) });
  });
}

tasks.post('/tasks/:id/copy', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const row = await loadTask(db, parseId(c.req.param('id')), me);
  assertCanEdit(me, row);
  const id = await insertTask(db, {
    ...row,
    checklist: JSON.parse(row.checklist || '[]').map((i) => ({ ...i, done: false })),
    attachments: JSON.parse(row.attachments || '[]'),
    distribution_item_id: null,
    group_id: null,
    created_by: me.id,
  });
  const fresh = await first(db, `${TASK_SELECT} WHERE t.id = ?`, id);
  await notifyAssigned(fromRequest(c), fresh, me.id);
  return c.json({ task: serializeTask(fresh) }, 201);
});

tasks.post('/tasks/bulk', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const body = parse(await readJson(c), {
    ids: v.array(v.id(), { min: 1, max: 200 }),
    action: v.enum(['delete', 'archive', 'reassign', 'reschedule']),
    assigneeId: v.id({ optional: true }),
    dueDate: v.date({ optional: true }),
  });
  if (body.action === 'reassign') {
    if (!body.assigneeId) throw badRequest('اختر العضو', { assigneeId: 'اختر العضو' });
    await assertMembers(db, [body.assigneeId]);
  }
  if (body.action === 'reschedule' && !body.dueDate) throw badRequest('اختر التاريخ', { dueDate: 'اختر التاريخ' });
  const rows = await all(db, `${TASK_SELECT} WHERE t.id IN (${inList(body.ids)}) AND t.deleted_at IS NULL`, ...body.ids);
  for (const row of rows) assertCanEdit(me, row);
  const ctx = fromRequest(c);
  const results = {};
  for (const row of rows) {
    if (body.action === 'delete') results[row.id] = await softDelete(c, row, me);
    else if (body.action === 'archive') {
      await run(db, 'UPDATE tasks SET archived_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
      await logActivity(db, 'task', row.id, me.id, 'archived');
      results[row.id] = 'archived';
    } else if (body.action === 'reassign' && row.kind !== 'personal') {
      if (row.assignee_id === body.assigneeId) continue;
      await run(db, 'UPDATE tasks SET assignee_id = ?, updated_at = ? WHERE id = ?', body.assigneeId, nowIso(), row.id);
      await logActivity(db, 'task', row.id, me.id, 'updated', { assigneeId: body.assigneeId });
      await notifyAssigned(ctx, { ...row, assignee_id: body.assigneeId }, me.id);
      results[row.id] = 'reassigned';
    } else if (body.action === 'reschedule') {
      await run(db, 'UPDATE tasks SET due_date = ?, reminded_at = NULL, overdue_notified_at = NULL, updated_at = ? WHERE id = ?', body.dueDate, nowIso(), row.id);
      await logActivity(db, 'task', row.id, me.id, 'updated', { dueDate: body.dueDate });
      if (row.kind !== 'personal' && row.assignee_id && row.assignee_id !== me.id) {
        await notify(ctx, [row.assignee_id], { type: 'task_updated', title: 'تغيّر موعد مهمتك', body: row.title, link: taskLink(row.id) });
      }
      results[row.id] = 'rescheduled';
    }
  }
  return c.json({ results });
});

export default tasks;
