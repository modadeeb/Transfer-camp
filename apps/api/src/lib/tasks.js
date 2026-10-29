import { KIND_LABELS, adenDate, defaultNeedsApproval, formatDate, nextOccurrence } from '@camp/domain';
import { isManager } from './auth.js';
import { all, camel, first, inList, logActivity, nowIso, run } from './db.js';
import { forbidden, notFound } from './http.js';
import { notify } from './notify.js';

export const TASK_SELECT = `
  SELECT t.*, u.name AS assignee_name, u.color AS assignee_color, p.name AS project_name, c.icon AS chore_icon
  FROM tasks t
  LEFT JOIN users u ON u.id = t.assignee_id
  LEFT JOIN projects p ON p.id = t.project_id
  LEFT JOIN chores c ON c.id = t.chore_id`;

export const serializeTask = (row) => camel(row, { omit: ['reminded_at', 'overdue_notified_at'] });

export function canView(user, task) {
  if (task.kind === 'personal') return task.assignee_id === user.id;
  return true;
}

export function canEdit(user, task) {
  if (task.kind === 'personal') return task.assignee_id === user.id;
  return isManager(user);
}

/** Loads a task the user may see; deleted tasks only when includeDeleted. */
export async function loadTask(db, id, user, { includeDeleted = false } = {}) {
  const row = await first(db, `${TASK_SELECT} WHERE t.id = ? ${includeDeleted ? '' : 'AND t.deleted_at IS NULL'}`, id);
  if (!row || !canView(user, row)) throw notFound('المهمة غير موجودة');
  return row;
}

export const managerIds = async (db) =>
  (await all(db, "SELECT id FROM users WHERE role = 'manager' AND deleted_at IS NULL AND archived_at IS NULL")).map((r) => r.id);

const randomId = () => Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => b.toString(36).padStart(2, '0')).join('').slice(0, 10);

export function normalizeChecklist(items = []) {
  return (items || [])
    .filter((i) => i && typeof i.text === 'string' && i.text.trim())
    .slice(0, 50)
    .map((i) => ({ id: typeof i.id === 'string' && i.id ? i.id.slice(0, 20) : randomId(), text: i.text.trim().slice(0, 200), done: Boolean(i.done) }));
}

export const taskLink = (id) => `/task/${id}`;

function dueText(t) {
  if (!t.due_date && !t.dueDate) return '';
  return ` · ${formatDate(t.due_date ?? t.dueDate, { weekday: true })}`;
}

/** Insert one task row and return its id. `data` uses snake_case column names. */
export async function insertTask(db, data) {
  const now = nowIso();
  const mx = await first(db, 'SELECT COALESCE(MAX(sort_order), 0) AS mx FROM tasks');
  const row = {
    kind: data.kind,
    title: data.title,
    details: data.details ?? null,
    assignee_id: data.assignee_id ?? null,
    project_id: data.project_id ?? null,
    chore_id: data.chore_id ?? null,
    distribution_item_id: data.distribution_item_id ?? null,
    specialty: data.specialty ?? null,
    due_date: data.due_date ?? null,
    due_time: data.due_time ?? null,
    priority: data.priority || 'normal',
    size: data.size ?? 1,
    recurrence: data.recurrence || 'none',
    needs_approval: data.needs_approval ?? (defaultNeedsApproval(data.kind) ? 1 : 0),
    status: 'pending',
    checklist: JSON.stringify(normalizeChecklist(data.checklist)),
    attachments: JSON.stringify(data.attachments || []),
    group_id: data.group_id ?? null,
    sort_order: mx.mx + 1,
    created_by: data.created_by ?? null,
    created_at: now,
    updated_at: now,
  };
  const keys = Object.keys(row);
  const r = await run(db, `INSERT INTO tasks (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`, ...keys.map((k) => row[k]));
  const id = r.meta.last_row_id;
  await logActivity(db, 'task', id, data.created_by ?? null, 'created');
  return id;
}

export async function notifyAssigned(ctx, task, actorId) {
  if (task.kind === 'personal' || !task.assignee_id || task.assignee_id === actorId) return;
  await notify(ctx, [task.assignee_id], {
    type: 'task_assigned',
    title: `مهمة ${KIND_LABELS[task.kind]} جديدة`,
    body: `${task.title}${dueText(task)}`,
    link: taskLink(task.id),
    urgent: task.priority === 'urgent',
  });
}

/** When a recurring task is completed, create the next occurrence once. */
export async function spawnNextOccurrence(db, task) {
  if (!task.recurrence || task.recurrence === 'none' || !task.due_date) return null;
  const nextDate = nextOccurrence(task.due_date, task.recurrence);
  const exists = await first(
    db,
    'SELECT id FROM tasks WHERE kind = ? AND title = ? AND assignee_id IS ? AND due_date = ? AND deleted_at IS NULL',
    task.kind,
    task.title,
    task.assignee_id,
    nextDate,
  );
  if (exists) return null;
  return insertTask(db, {
    ...task,
    checklist: JSON.parse(task.checklist || '[]').map((i) => ({ ...i, done: false })),
    attachments: JSON.parse(task.attachments || '[]'),
    due_date: nextDate,
    distribution_item_id: null,
  });
}

/** House points this week + carried balance; used to auto-pick for manual house tasks. */
export async function leastLoadedForHouse(db, memberIds, weekStart, weekEnd) {
  if (!memberIds.length) return null;
  const rows = await all(
    db,
    `SELECT u.id, u.distribution_balance AS balance, u.sort_order,
       COALESCE((SELECT SUM(size) FROM tasks t WHERE t.assignee_id = u.id AND t.kind = 'house' AND t.deleted_at IS NULL
                 AND t.due_date BETWEEN ? AND ?), 0) AS pts
     FROM users u WHERE u.id IN (${inList(memberIds)})`,
    weekStart,
    weekEnd,
    ...memberIds,
  );
  rows.sort((a, b) => a.balance + a.pts - (b.balance + b.pts) || a.sort_order - b.sort_order || a.id - b.id);
  return rows[0]?.id ?? null;
}

export function assertCanEdit(user, task) {
  if (!canEdit(user, task)) throw forbidden(task.kind === 'personal' ? 'هذه مهمة شخصية لغيرك' : 'إدارة المهام المشتركة للمدير فقط');
}

export const todayAden = () => adenDate();
