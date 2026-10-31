// Home dashboard, group/personal schedules and the fairness board.
import { Hono } from 'hono';
import { addDays, adenDate, adenTime, fairnessReport, isDate, weekDates, weekStartOf } from '@camp/domain';
import { isManager, publicUser } from '../lib/auth.js';
import { all, camelAll, first, getSetting } from '../lib/db.js';
import { TASK_SELECT, serializeTask } from '../lib/tasks.js';
import { budgetView } from './budget.js';
import { activeMembers } from './members.js';
import { prayerTimes } from '../lib/prayers.js';

const overview = new Hono();

const eventForUser = (userId) => (e) => e.everyone || JSON.parse(e.member_ids || '[]').includes(userId);

overview.get('/home', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const today = adenDate();
  const nowTime = adenTime();
  const weekStart = weekStartOf(today);

  const myTasks = await all(
    db,
    `${TASK_SELECT} WHERE t.assignee_id = ? AND t.deleted_at IS NULL AND t.archived_at IS NULL
       AND (t.due_date = ? OR (t.due_date < ? AND t.status != 'approved') OR (t.due_date IS NULL AND t.status IN ('in_progress','returned')))
     ORDER BY t.sort_order, t.due_date, t.due_time IS NULL, t.due_time, t.id`,
    me.id,
    today,
    today,
  );
  const events = (await all(db, 'SELECT * FROM events WHERE deleted_at IS NULL AND date = ? ORDER BY start_time', today)).filter(eventForUser(me.id));
  const prayers = (await all(db, 'SELECT prayer FROM prayer_logs WHERE user_id = ? AND date = ?', me.id, today)).map((r) => r.prayer);
  const swaps = await all(
    db,
    `SELECT s.id, s.note, f.name AS from_name, t.title AS task_title, t.due_date AS task_due_date
     FROM swap_requests s JOIN users f ON f.id = s.from_user_id JOIN tasks t ON t.id = s.task_id
     WHERE s.to_user_id = ? AND s.status = 'pending' AND s.deleted_at IS NULL ORDER BY s.id DESC`,
    me.id,
  );
  const budget = await budgetView(db, me.id);
  const habits = await all(db, 'SELECT id, days FROM habits WHERE user_id = ? AND deleted_at IS NULL AND archived_at IS NULL', me.id);
  const habitDone = await first(
    db,
    'SELECT COUNT(*) AS n FROM habit_logs l JOIN habits h ON h.id = l.habit_id WHERE h.user_id = ? AND l.date = ? AND h.deleted_at IS NULL AND h.archived_at IS NULL',
    me.id,
    today,
  );
  const dow = new Date(`${today}T00:00:00Z`).getUTCDay();
  const habitsDue = habits.filter((h) => {
    const d = JSON.parse(h.days);
    return d === 'daily' || (Array.isArray(d) && d.includes(dow));
  }).length;
  const unread = await first(db, 'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL AND deleted_at IS NULL', me.id);
  const weekPoints = await first(
    db,
    "SELECT COALESCE(SUM(size), 0) AS pts, COALESCE(SUM(CASE WHEN status = 'approved' THEN size ELSE 0 END), 0) AS done FROM tasks WHERE assignee_id = ? AND kind = 'house' AND deleted_at IS NULL AND due_date BETWEEN ? AND ?",
    me.id,
    weekStart,
    addDays(weekStart, 6),
  );
  const workouts = await first(db, 'SELECT COUNT(DISTINCT date) AS n FROM workouts WHERE user_id = ? AND date BETWEEN ? AND ?', me.id, weekStart, addDays(weekStart, 6));
  const sleep = await first(db, 'SELECT slept_at, woke_at FROM sleep_logs WHERE user_id = ? AND date = ?', me.id, today);

  const contributionsDue = (
    await all(
      db,
      `SELECT c.id, c.amount_due, cp.title, cp.due_date,
         COALESCE((SELECT SUM(amount) FROM contribution_payments p WHERE p.contribution_id = c.id AND p.deleted_at IS NULL), 0) AS paid
       FROM contributions c JOIN contribution_periods cp ON cp.id = c.period_id AND cp.deleted_at IS NULL WHERE c.user_id = ?`,
      me.id,
    )
  )
    .map((r) => ({ id: r.id, title: r.title, dueDate: r.due_date, remaining: r.amount_due - r.paid, overdue: Boolean(r.due_date && r.due_date < today) }))
    .filter((r) => r.remaining > 0);

  const manager = isManager(me)
    ? {
        pendingApprovals: (await first(db, "SELECT COUNT(*) AS n FROM tasks WHERE status = 'submitted' AND deleted_at IS NULL AND archived_at IS NULL AND kind != 'personal'")).n,
        overdue: (
          await first(
            db,
            "SELECT COUNT(*) AS n FROM tasks WHERE kind != 'personal' AND status != 'approved' AND deleted_at IS NULL AND archived_at IS NULL AND due_date IS NOT NULL AND (due_date < ? OR (due_date = ? AND due_time IS NOT NULL AND due_time < ?))",
            today,
            today,
            nowTime,
          )
        ).n,
        nextWeekDistribution: (await first(db, 'SELECT status FROM distributions WHERE week_start = ?', addDays(weekStart, 7)))?.status || null,
        thisWeekDistribution: (await first(db, 'SELECT status FROM distributions WHERE week_start = ?', weekStart))?.status || null,
        pendingSwaps: (await first(db, "SELECT COUNT(*) AS n FROM swap_requests WHERE status = 'pending' AND deleted_at IS NULL")).n,
      }
    : null;

  return c.json({
    campName: await getSetting(db, 'camp_name', 'معسكر نقلة'),
    today,
    nowTime,
    weekStart,
    tasks: myTasks.map(serializeTask),
    events: camelAll(events),
    prayers,
    prayerTimes: prayerTimes(today),
    swaps: camelAll(swaps),
    budget: budget.week ? { week: budget.week, summary: budget.summary } : null,
    contributionsDue,
    habits: { due: habitsDue, done: habitDone.n },
    housePoints: weekPoints,
    workoutsThisWeek: workouts.n,
    sleep: sleep ? { sleptAt: sleep.slept_at, wokeAt: sleep.woke_at } : null,
    unread: unread.n,
    manager,
  });
});

function weekParam(c) {
  const q = c.req.query('weekStart');
  return weekStartOf(isDate(q) ? q : adenDate());
}

overview.get('/schedule/group', async (c) => {
  const db = c.env.DB;
  const weekStart = weekParam(c);
  const weekEnd = addDays(weekStart, 6);
  const members = await activeMembers(db);
  const tasks = await all(
    db,
    `${TASK_SELECT} WHERE t.kind IN ('house','company') AND t.deleted_at IS NULL AND t.due_date BETWEEN ? AND ?
     ORDER BY t.due_date, t.due_time IS NULL, t.due_time, t.sort_order, t.id`,
    weekStart,
    weekEnd,
  );
  const events = await all(db, 'SELECT * FROM events WHERE deleted_at IS NULL AND date BETWEEN ? AND ? ORDER BY date, start_time', weekStart, weekEnd);
  const absences = await all(
    db,
    'SELECT a.*, u.name AS user_name FROM absences a JOIN users u ON u.id = a.user_id WHERE a.deleted_at IS NULL AND a.start_date <= ? AND a.end_date >= ?',
    weekEnd,
    weekStart,
  );
  const dist = await first(db, 'SELECT status FROM distributions WHERE week_start = ?', weekStart);
  return c.json({
    weekStart,
    dates: weekDates(weekStart),
    today: adenDate(),
    members: members.map(publicUser),
    tasks: tasks.map(serializeTask),
    events: camelAll(events),
    absences: camelAll(absences),
    distributionStatus: dist?.status || null,
  });
});

overview.get('/schedule/me', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const weekStart = weekParam(c);
  const weekEnd = addDays(weekStart, 6);
  const tasks = await all(
    db,
    `${TASK_SELECT} WHERE t.assignee_id = ? AND t.deleted_at IS NULL AND t.archived_at IS NULL
       AND (t.due_date BETWEEN ? AND ? OR (t.due_date IS NULL AND t.status != 'approved'))
     ORDER BY t.due_date IS NULL, t.due_date, t.due_time IS NULL, t.due_time, t.sort_order, t.id`,
    me.id,
    weekStart,
    weekEnd,
  );
  const slots = await all(db, 'SELECT * FROM member_slots WHERE user_id = ? ORDER BY dow, start_time', me.id);
  const events = (await all(db, 'SELECT * FROM events WHERE deleted_at IS NULL AND date BETWEEN ? AND ? ORDER BY date, start_time', weekStart, weekEnd)).filter(
    eventForUser(me.id),
  );
  const absences = await all(db, 'SELECT * FROM absences WHERE user_id = ? AND deleted_at IS NULL AND start_date <= ? AND end_date >= ?', me.id, weekEnd, weekStart);
  return c.json({
    weekStart,
    dates: weekDates(weekStart),
    today: adenDate(),
    tasks: tasks.map(serializeTask),
    slots: camelAll(slots),
    events: camelAll(events),
    absences: camelAll(absences),
  });
});

overview.get('/fairness', async (c) => {
  const db = c.env.DB;
  const today = adenDate();
  const period = c.req.query('period') === 'month' ? 'month' : 'week';
  const anchor = isDate(c.req.query('date')) ? c.req.query('date') : today;
  let from;
  let to;
  if (period === 'month') {
    from = `${anchor.slice(0, 7)}-01`;
    const [y, m] = anchor.split('-').map(Number);
    to = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
  } else {
    from = weekStartOf(anchor);
    to = addDays(from, 6);
  }
  const members = await activeMembers(db);
  const tasks = await all(
    db,
    "SELECT kind, assignee_id, size, status, due_date, deleted_at FROM tasks WHERE kind != 'personal' AND deleted_at IS NULL AND due_date BETWEEN ? AND ?",
    from,
    to,
  );
  const report = fairnessReport({
    members: members.map((m) => ({ id: m.id, balance: m.distribution_balance })),
    tasks: camelAll(tasks),
    from,
    to,
    today,
  });
  return c.json({
    period,
    from,
    to,
    today,
    rows: report.map((r) => {
      const m = members.find((x) => x.id === r.userId);
      return { ...r, name: m.name, color: m.color, specialty: m.specialty };
    }),
  });
});

export default overview;
