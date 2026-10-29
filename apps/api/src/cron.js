// Runs every 15 minutes (wrangler cron "*/15 * * * *"). Each job guards itself so repeats are harmless.
import { addDays, adenDate, adenTime, adenToInstant, dayOfWeek, formatMoney, formatTime, weekStartOf } from '@camp/domain';
import { all, first, getSetting, nowIso, run, setSetting } from './lib/db.js';
import { notify } from './lib/notify.js';
import { managerIds, taskLink } from './lib/tasks.js';
import { buildDraft } from './routes/housing.js';
import { TRASH_DAYS } from './routes/common.js';

const REMIND_BEFORE_MIN = 120;

async function onceAt(db, key, today, fn) {
  if ((await getSetting(db, key)) === today) return false;
  await setSetting(db, key, today);
  await fn();
  return true;
}

export async function reminders(ctx, now) {
  const db = ctx.env.DB;
  const today = adenDate(now);
  const rows = await all(
    db,
    `SELECT * FROM tasks WHERE deleted_at IS NULL AND archived_at IS NULL AND status IN ('pending','in_progress','returned')
       AND assignee_id IS NOT NULL AND due_date BETWEEN ? AND ? AND due_time IS NOT NULL AND reminded_at IS NULL`,
    today,
    addDays(today, 1),
  );
  let sent = 0;
  for (const t of rows) {
    const due = adenToInstant(t.due_date, t.due_time).getTime();
    const mins = (due - now.getTime()) / 60000;
    if (mins > REMIND_BEFORE_MIN || mins < 0) continue;
    const lock = await run(db, 'UPDATE tasks SET reminded_at = ? WHERE id = ? AND reminded_at IS NULL', nowIso(), t.id);
    if (!lock.meta.changes) continue;
    await notify(ctx, [t.assignee_id], {
      type: 'task_reminder',
      title: `⏰ ${t.title}`,
      body: `موعدها ${formatTime(t.due_time)}`,
      link: taskLink(t.id),
      urgent: t.priority === 'urgent',
    });
    sent += 1;
  }
  return sent;
}

export async function overdue(ctx, now) {
  const db = ctx.env.DB;
  const today = adenDate(now);
  const time = adenTime(now);
  const rows = await all(
    db,
    `SELECT * FROM tasks WHERE deleted_at IS NULL AND archived_at IS NULL AND status IN ('pending','in_progress','returned')
       AND assignee_id IS NOT NULL AND overdue_notified_at IS NULL AND due_date IS NOT NULL
       AND (due_date < ? OR (due_date = ? AND due_time IS NOT NULL AND due_time <= ?))`,
    today,
    today,
    time,
  );
  let sent = 0;
  for (const t of rows) {
    const lock = await run(db, 'UPDATE tasks SET overdue_notified_at = ? WHERE id = ? AND overdue_notified_at IS NULL', nowIso(), t.id);
    if (!lock.meta.changes) continue;
    await notify(ctx, [t.assignee_id], {
      type: 'task_overdue',
      title: 'مهمة تجاوزت موعدها',
      body: `${t.title} — لا بأس، أنجزها متى استطعت`,
      link: taskLink(t.id),
    });
    sent += 1;
  }
  return sent;
}

export async function morningSummary(ctx, now) {
  const db = ctx.env.DB;
  const today = adenDate(now);
  const users = await all(db, 'SELECT id, role FROM users WHERE deleted_at IS NULL AND archived_at IS NULL');
  for (const u of users) {
    const counts = await first(
      db,
      `SELECT COUNT(*) AS n, SUM(CASE WHEN kind = 'house' THEN 1 ELSE 0 END) AS house, SUM(CASE WHEN kind = 'company' THEN 1 ELSE 0 END) AS company
       FROM tasks WHERE assignee_id = ? AND due_date = ? AND deleted_at IS NULL AND archived_at IS NULL AND status != 'approved'`,
      u.id,
      today,
    );
    if (!counts.n) continue;
    const parts = [];
    if (counts.house) parts.push(`${counts.house} سكن`);
    if (counts.company) parts.push(`${counts.company} شركة`);
    const personal = counts.n - (counts.house || 0) - (counts.company || 0);
    if (personal) parts.push(`${personal} شخصية`);
    await notify(ctx, [u.id], { type: 'morning_summary', title: 'صباح الخير ☀️', body: `مهامك اليوم: ${parts.join(' · ')}`, link: '/' });
  }
  const overdueCount = await first(
    db,
    "SELECT COUNT(*) AS n FROM tasks WHERE kind != 'personal' AND status != 'approved' AND deleted_at IS NULL AND archived_at IS NULL AND due_date < ?",
    today,
  );
  const pending = await first(db, "SELECT COUNT(*) AS n FROM tasks WHERE status = 'submitted' AND deleted_at IS NULL AND kind != 'personal'");
  if (overdueCount.n || pending.n) {
    const parts = [];
    if (pending.n) parts.push(`${pending.n} بانتظار الاعتماد`);
    if (overdueCount.n) parts.push(`${overdueCount.n} متأخرة`);
    await notify(ctx, await managerIds(db), { type: 'overdue_summary', title: 'ملخص المهام', body: parts.join(' · '), link: '/work?tab=manage' });
  }
}

export async function contributionReminders(ctx, now) {
  const db = ctx.env.DB;
  const today = adenDate(now);
  const rows = await all(
    db,
    `SELECT c.user_id, cp.title, c.amount_due,
       COALESCE((SELECT SUM(amount) FROM contribution_payments p WHERE p.contribution_id = c.id AND p.deleted_at IS NULL), 0) AS paid
     FROM contributions c JOIN contribution_periods cp ON cp.id = c.period_id AND cp.deleted_at IS NULL
     WHERE cp.due_date IS NOT NULL AND cp.due_date < ?`,
    today,
  );
  for (const r of rows.filter((x) => x.amount_due > x.paid)) {
    await notify(ctx, [r.user_id], {
      type: 'contribution_due',
      title: 'مساهمة الصندوق متأخرة',
      body: `${r.title}: المتبقي ${formatMoney(r.amount_due - r.paid)}`,
      link: '/money',
    });
  }
}

export async function weeklyDraft(ctx, now) {
  const db = ctx.env.DB;
  const next = addDays(weekStartOf(adenDate(now)), 7);
  if (await first(db, 'SELECT id FROM distributions WHERE week_start = ?', next)) return false;
  const chores = await first(db, 'SELECT COUNT(*) AS n FROM chores WHERE deleted_at IS NULL AND archived_at IS NULL AND active = 1');
  if (!chores.n) return false;
  await buildDraft(db, next);
  await notify(ctx, await managerIds(db), {
    type: 'distribution',
    title: 'مسودة توزيع الأسبوع القادم جاهزة',
    body: 'راجعها واعتمدها لتصل المهام للجميع',
    link: `/housing?tab=distribution&week=${next}`,
  });
  return true;
}

export async function cleanup(env, now) {
  const db = env.DB;
  const cutoff = new Date(now.getTime() - TRASH_DAYS * 86400000).toISOString();
  for (const table of ['tasks', 'chores', 'projects', 'events', 'shared_expenses', 'goals', 'habits', 'notifications', 'settlements', 'absences']) {
    if (table === 'tasks') {
      // keep tasks that a distribution item still points to
      await run(db, `DELETE FROM swap_requests WHERE task_id IN (SELECT id FROM tasks WHERE deleted_at < ?) OR counter_task_id IN (SELECT id FROM tasks WHERE deleted_at < ?)`, cutoff, cutoff);
      await run(db, 'UPDATE distribution_items SET task_id = NULL WHERE task_id IN (SELECT id FROM tasks WHERE deleted_at < ?)', cutoff);
    }
    if (table === 'chores' || table === 'projects') {
      // soft-deleted chores/projects stay referenced by history; only purge when unreferenced
      const ref = table === 'chores' ? 'chore_id' : 'project_id';
      await run(
        db,
        `DELETE FROM ${table} WHERE deleted_at < ? AND id NOT IN (SELECT ${ref} FROM tasks WHERE ${ref} IS NOT NULL)
         ${table === 'chores' ? 'AND id NOT IN (SELECT chore_id FROM distribution_items)' : ''}`,
        cutoff,
      );
      continue;
    }
    await run(db, `DELETE FROM ${table} WHERE deleted_at IS NOT NULL AND deleted_at < ?`, cutoff);
  }
  await run(db, 'DELETE FROM notifications WHERE read_at IS NOT NULL AND created_at < ?', new Date(now.getTime() - 90 * 86400000).toISOString());
  await run(db, 'DELETE FROM login_attempts WHERE created_at < ?', new Date(now.getTime() - 86400000).toISOString());
}

/** Entry point for the Workers `scheduled` event. */
export async function runScheduled(env, now = new Date(), waitUntil) {
  const ctx = { env, waitUntil };
  const today = adenDate(now);
  const time = adenTime(now);
  const results = { reminders: await reminders(ctx, now), overdue: await overdue(ctx, now) };
  if (time >= '07:00') {
    results.morning = await onceAt(env.DB, 'cron_morning', today, () => morningSummary(ctx, now));
    if (dayOfWeek(today) === 6) results.contributions = await onceAt(env.DB, 'cron_contributions', today, () => contributionReminders(ctx, now));
  }
  if (dayOfWeek(today) === 4 && time >= '18:00') {
    results.draft = await onceAt(env.DB, 'cron_weekly_draft', today, () => weeklyDraft(ctx, now));
  }
  if (time >= '03:00') results.cleanup = await onceAt(env.DB, 'cron_cleanup', today, () => cleanup(env, now));
  return results;
}
