// Personal weekly budget (owner only). A budget week starts the day income arrives and lasts 7 days.
import { Hono } from 'hono';
import { addDays, adenDate, budgetSummary, contributionStatus, isDate } from '@camp/domain';
import { all, camel, camelAll, first, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, notFound, parseId, readJson } from '../lib/http.js';
import { parse, v } from '../lib/validate.js';

const budget = new Hono();

export const PERSONAL_CATEGORIES = {
  food: 'طعام',
  transport: 'مواصلات',
  study: 'دراسة',
  phone: 'اتصالات',
  personal: 'شخصي',
  other: 'أخرى',
};
export const INCOME_SOURCES = { salary: 'راتب', freelance: 'عمل حر', family: 'من الأهل', gift: 'هدية', other: 'أخرى' };

async function openWeek(db, userId) {
  return first(db, "SELECT * FROM budget_weeks WHERE user_id = ? AND status = 'open'", userId);
}

async function weekData(db, week) {
  const incomes = await all(db, 'SELECT * FROM budget_incomes WHERE week_id = ? ORDER BY date, id', week.id);
  const essentials = await all(db, 'SELECT * FROM budget_essentials WHERE week_id = ? ORDER BY id', week.id);
  const expenses = await all(db, 'SELECT * FROM budget_expenses WHERE week_id = ? ORDER BY date DESC, id DESC', week.id);
  return { incomes, essentials, expenses };
}

function summarize(week, data, today) {
  return budgetSummary({
    week: { startDate: week.start_date, endDate: week.end_date, carriedIn: week.carried_in },
    incomes: data.incomes,
    essentials: data.essentials,
    expenses: data.expenses.map((e) => ({ date: e.date, amount: e.amount })),
    today,
  });
}

/** Unpaid share of the shared fund (suggested as an automatic essential). */
async function fundShareDue(db, userId, today) {
  const rows = await all(
    db,
    `SELECT c.amount_due, cp.due_date, cp.title,
       COALESCE((SELECT SUM(amount) FROM contribution_payments p WHERE p.contribution_id = c.id AND p.deleted_at IS NULL), 0) AS paid
     FROM contributions c JOIN contribution_periods cp ON cp.id = c.period_id AND cp.deleted_at IS NULL WHERE c.user_id = ?`,
    userId,
  );
  return rows.reduce((s, r) => s + contributionStatus({ amountDue: r.amount_due, paid: r.paid, dueDate: r.due_date, today }).remaining, 0);
}

export async function budgetView(db, userId) {
  const today = adenDate();
  const week = await openWeek(db, userId);
  const fundShare = await fundShareDue(db, userId, today);
  if (!week) return { today, week: null, fundShareDue: fundShare, categories: PERSONAL_CATEGORIES, sources: INCOME_SOURCES };
  const data = await weekData(db, week);
  return {
    today,
    week: camel(week),
    incomes: camelAll(data.incomes),
    essentials: camelAll(data.essentials),
    expenses: camelAll(data.expenses),
    summary: summarize(week, data, today),
    fundShareDue: fundShare,
    categories: PERSONAL_CATEGORIES,
    sources: INCOME_SOURCES,
  };
}

budget.get('/budget', async (c) => c.json(await budgetView(c.env.DB, c.get('user').id)));

budget.get('/budget/weeks', async (c) => {
  const rows = await all(c.env.DB, "SELECT * FROM budget_weeks WHERE user_id = ? AND status = 'closed' ORDER BY start_date DESC LIMIT 52", c.get('user').id);
  return c.json({ weeks: camelAll(rows) });
});

/**
 * Start a new week. If one is open it is closed first: its leftover is carried
 * into the new week ("carry") or kept aside as savings ("save").
 */
budget.post('/budget/weeks', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const b = parse(await readJson(c), {
    income: v.money({ min: 0 }),
    source: v.enum(Object.keys(INCOME_SOURCES), { defaultValue: 'salary' }),
    essentials: v.array(v.object({ title: v.string({ max: 60 }), amount: v.money({ min: 0 }) }), { max: 30, optional: true }),
    leftover: v.enum(['carry', 'save'], { defaultValue: 'carry' }),
  });
  const today = adenDate();
  const current = await openWeek(db, me.id);
  let carried = 0;
  const now = nowIso();
  if (current) {
    if (current.start_date === today) throw conflict('بدأ هذا الأسبوع اليوم. عدّل دخله وأساسياته بدلاً من بدء أسبوع جديد');
    const data = await weekData(db, current);
    // the old week ends yesterday (or at its own end if that's earlier);
    // expenses dated today or later move to the new week
    const end = current.end_date < today ? current.end_date : addDays(today, -1);
    const s = summarize({ ...current, end_date: end }, { ...data, incomes: data.incomes.filter((e) => e.date <= end), expenses: data.expenses.filter((e) => e.date <= end) }, addDays(end, 1));
    const left = Math.max(0, s.left);
    carried = b.leftover === 'carry' ? left : 0;
    await run(
      db,
      "UPDATE budget_weeks SET status = 'closed', end_date = ?, saved_amount = ?, summary = ?, closed_at = ? WHERE id = ?",
      end,
      b.leftover === 'save' ? left : 0,
      JSON.stringify({ income: s.totalIncome, essentials: s.essentialsTotal, spent: s.spentTotal, left: s.left }),
      now,
      current.id,
    );
  }
  const r = await run(
    db,
    "INSERT INTO budget_weeks (user_id, start_date, end_date, carried_in, status, created_at) VALUES (?, ?, ?, ?, 'open', ?)",
    me.id,
    today,
    addDays(today, 6),
    carried,
    now,
  );
  const weekId = r.meta.last_row_id;
  if (current) {
    await run(db, 'UPDATE budget_expenses SET week_id = ? WHERE week_id = ? AND date > ?', weekId, current.id, addDays(today, -1));
    await run(db, 'UPDATE budget_incomes SET week_id = ? WHERE week_id = ? AND date > ?', weekId, current.id, addDays(today, -1));
  }
  if (b.income > 0) {
    await run(db, 'INSERT INTO budget_incomes (user_id, week_id, date, amount, source, created_at) VALUES (?, ?, ?, ?, ?, ?)', me.id, weekId, today, b.income, b.source, now);
  }
  for (const e of b.essentials || []) {
    await run(db, 'INSERT INTO budget_essentials (user_id, week_id, title, amount) VALUES (?, ?, ?, ?)', me.id, weekId, e.title, e.amount);
  }
  return c.json(await budgetView(db, me.id), 201);
});

async function requireOpen(db, userId) {
  const week = await openWeek(db, userId);
  if (!week) throw conflict('ابدأ أسبوعاً جديداً أولاً');
  return week;
}

function checkDate(week, date) {
  const today = adenDate();
  if (date > today) throw badRequest('لا يمكن التسجيل في المستقبل', { date: 'لا يمكن التسجيل في المستقبل' });
  if (date < week.start_date || date > week.end_date) throw badRequest('التاريخ خارج الأسبوع الحالي', { date: 'التاريخ خارج الأسبوع الحالي' });
}

const ENTRY_TABLES = {
  incomes: {
    table: 'budget_incomes',
    schema: { amount: v.money(), date: v.date({ optional: true }), source: v.enum(Object.keys(INCOME_SOURCES), { defaultValue: 'other' }), note: v.string({ max: 200, optional: true }) },
    cols: { amount: 'amount', date: 'date', source: 'source', note: 'note' },
  },
  expenses: {
    table: 'budget_expenses',
    schema: { amount: v.money(), date: v.date({ optional: true }), category: v.enum(Object.keys(PERSONAL_CATEGORIES), { defaultValue: 'other' }), note: v.string({ max: 200, optional: true }) },
    cols: { amount: 'amount', date: 'date', category: 'category', note: 'note' },
  },
  essentials: {
    table: 'budget_essentials',
    schema: { title: v.string({ max: 60 }), amount: v.money({ min: 0 }) },
    cols: { title: 'title', amount: 'amount' },
  },
};

for (const [name, def] of Object.entries(ENTRY_TABLES)) {
  const dated = 'date' in def.cols;

  budget.post(`/budget/${name}`, async (c) => {
    const me = c.get('user');
    const week = await requireOpen(c.env.DB, me.id);
    const b = parse(await readJson(c), def.schema);
    if (dated) {
      b.date = b.date || adenDate();
      checkDate(week, b.date);
    }
    const data = { user_id: me.id, week_id: week.id, ...Object.fromEntries(Object.entries(def.cols).map(([k, col]) => [col, b[k]])) };
    if (dated) data.created_at = nowIso();
    const keys = Object.keys(data);
    await run(c.env.DB, `INSERT INTO ${def.table} (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`, ...keys.map((k) => data[k]));
    return c.json(await budgetView(c.env.DB, me.id), 201);
  });

  budget.patch(`/budget/${name}/:id`, async (c) => {
    const me = c.get('user');
    const week = await requireOpen(c.env.DB, me.id);
    const row = await first(c.env.DB, `SELECT * FROM ${def.table} WHERE id = ? AND user_id = ? AND week_id = ?`, parseId(c.req.param('id')), me.id, week.id);
    if (!row) throw notFound();
    const b = parse(await readJson(c), def.schema, { partial: true });
    if (dated && b.date) checkDate(week, b.date);
    const entries = Object.entries(def.cols).filter(([k]) => b[k] !== undefined);
    if (entries.length) {
      await run(c.env.DB, `UPDATE ${def.table} SET ${entries.map(([, col]) => `${col} = ?`).join(', ')} WHERE id = ?`, ...entries.map(([k]) => b[k]), row.id);
    }
    return c.json(await budgetView(c.env.DB, me.id));
  });

  budget.delete(`/budget/${name}/:id`, async (c) => {
    const me = c.get('user');
    const r = await run(c.env.DB, `DELETE FROM ${def.table} WHERE id = ? AND user_id = ?`, parseId(c.req.param('id')), me.id);
    if (!r.meta.changes) throw notFound();
    return c.json(await budgetView(c.env.DB, me.id));
  });

  if (name !== 'essentials') {
    budget.post(`/budget/${name}/:id/copy`, async (c) => {
      const me = c.get('user');
      const week = await requireOpen(c.env.DB, me.id);
      const row = await first(c.env.DB, `SELECT * FROM ${def.table} WHERE id = ? AND user_id = ?`, parseId(c.req.param('id')), me.id);
      if (!row) throw notFound();
      const data = { user_id: me.id, week_id: week.id, ...Object.fromEntries(Object.values(def.cols).map((col) => [col, row[col]])), date: adenDate(), created_at: nowIso() };
      const keys = Object.keys(data);
      await run(c.env.DB, `INSERT INTO ${def.table} (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`, ...keys.map((k) => data[k]));
      return c.json(await budgetView(c.env.DB, me.id), 201);
    });
  }
}

budget.get('/budget/preview', async (c) => {
  const me = c.get('user');
  const week = await openWeek(c.env.DB, me.id);
  if (!week) return c.json({ allowedToday: null });
  const data = await weekData(c.env.DB, week);
  const expense = Number(c.req.query('expense') || 0);
  const income = Number(c.req.query('income') || 0);
  const date = isDate(c.req.query('date')) ? c.req.query('date') : adenDate();
  const today = adenDate();
  const s = summarize(
    week,
    {
      ...data,
      incomes: [...data.incomes, { amount: income }],
      expenses: [...data.expenses, { date, amount: expense }],
    },
    today,
  );
  return c.json({ allowedToday: s.allowedToday, leftToday: s.leftToday, overToday: s.overToday });
});

export default budget;
