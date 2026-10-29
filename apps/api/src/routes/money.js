// Shared fund, shared expenses, settlements and debts between members.
import { Hono } from 'hono';
import { adenDate, contributionStatus, debtRemaining, formatMoney, fundBalance, memberNets, settlementPlan, splitAmount } from '@camp/domain';
import { assertManager, isManager } from '../lib/auth.js';
import { all, camel, camelAll, first, inList, logActivity, nowIso, run } from '../lib/db.js';
import { badRequest, conflict, forbidden, notFound, parseId, readJson } from '../lib/http.js';
import { fromRequest, notify } from '../lib/notify.js';
import { parse, v } from '../lib/validate.js';
import { activeMembers } from './members.js';

const money = new Hono();

export const EXPENSE_CATEGORIES = {
  rent: 'إيجار',
  electricity: 'كهرباء',
  water: 'ماء',
  internet: 'إنترنت',
  groceries: 'مشتريات المطبخ',
  cleaning: 'منظفات',
  gas: 'غاز',
  maintenance: 'صيانة',
  other: 'أخرى',
};

async function memberIdsCheck(db, ids) {
  if (!ids.length) return;
  const rows = await all(db, `SELECT id FROM users WHERE id IN (${inList(ids)}) AND deleted_at IS NULL`, ...ids);
  if (rows.length !== new Set(ids).size) throw badRequest('أحد الأعضاء غير موجود');
}

/** Everything the money page needs, computed from the ledger. */
export async function fundOverview(db, me) {
  const today = adenDate();
  const members = await all(db, 'SELECT id, name, color, sort_order, archived_at FROM users WHERE deleted_at IS NULL ORDER BY sort_order, id');
  const periods = await all(db, 'SELECT * FROM contribution_periods WHERE deleted_at IS NULL ORDER BY COALESCE(due_date, created_at) DESC, id DESC');
  const contributions = await all(
    db,
    `SELECT c.*, u.name AS user_name, u.color AS user_color,
       COALESCE((SELECT SUM(amount) FROM contribution_payments p WHERE p.contribution_id = c.id AND p.deleted_at IS NULL), 0) AS paid
     FROM contributions c JOIN users u ON u.id = c.user_id
     JOIN contribution_periods cp ON cp.id = c.period_id AND cp.deleted_at IS NULL
     ORDER BY u.sort_order, u.id`,
  );
  const payments = await all(
    db,
    `SELECT p.* FROM contribution_payments p JOIN contributions c ON c.id = p.contribution_id
     JOIN contribution_periods cp ON cp.id = c.period_id AND cp.deleted_at IS NULL WHERE p.deleted_at IS NULL`,
  );
  const expenses = await all(db, 'SELECT * FROM shared_expenses WHERE deleted_at IS NULL');
  const debts = await all(db, 'SELECT * FROM debts WHERE deleted_at IS NULL');
  const debtPayments = await all(db, 'SELECT p.* FROM debt_payments p JOIN debts d ON d.id = p.debt_id AND d.deleted_at IS NULL');
  const settlements = await all(db, 'SELECT * FROM settlements WHERE deleted_at IS NULL');

  const fund = fundBalance({
    contributionPayments: payments.map((p) => ({ amount: p.amount })),
    expenses: expenses.map((e) => ({ amount: e.amount, paidFromFund: Boolean(e.paid_from_fund) })),
  });
  const nets = memberNets({
    memberIds: members.map((m) => m.id),
    expenses: expenses.map((e) => ({
      amount: e.amount,
      paidFromFund: Boolean(e.paid_from_fund),
      payerId: e.payer_id,
      splitMemberIds: JSON.parse(e.split_member_ids || '[]'),
    })),
    debts: debts.map((d) => ({ id: d.id, creditorId: d.creditor_id, debtorId: d.debtor_id, amount: d.amount })),
    debtPayments: debtPayments.map((p) => ({ debtId: p.debt_id, amount: p.amount })),
    settlements: settlements.map((s) => ({ fromId: s.from_user_id, toId: s.to_user_id, amount: s.amount })),
  });
  const name = (id) => members.find((m) => m.id === id)?.name || '';

  const periodRows = periods.map((p) => {
    const rows = contributions
      .filter((c) => c.period_id === p.id)
      .map((c) => ({ ...camel(c), ...contributionStatus({ amountDue: c.amount_due, paid: c.paid, dueDate: p.due_date, today }) }));
    return {
      ...camel(p),
      totalDue: rows.reduce((s, r) => s + r.amountDue, 0),
      totalPaid: rows.reduce((s, r) => s + r.paid, 0),
      contributions: rows,
    };
  });

  const myContributions = periodRows.flatMap((p) => p.contributions.filter((c) => c.userId === me.id).map((c) => ({ ...c, periodTitle: p.title, dueDate: p.dueDate })));
  return {
    today,
    fund,
    periods: periodRows,
    members: members.map((m) => ({ id: m.id, name: m.name, color: m.color, archived: Boolean(m.archived_at), net: nets.get(m.id) || 0 })),
    plan: settlementPlan(nets).map((t) => ({ ...t, fromName: name(t.fromId), toName: name(t.toId) })),
    me: {
      net: nets.get(me.id) || 0,
      owedToMe: settlementPlan(nets).filter((t) => t.toId === me.id).map((t) => ({ ...t, name: name(t.fromId) })),
      iOwe: settlementPlan(nets).filter((t) => t.fromId === me.id).map((t) => ({ ...t, name: name(t.toId) })),
      contributionsDue: myContributions.filter((c) => c.remaining > 0),
    },
    categories: EXPENSE_CATEGORIES,
  };
}

money.get('/fund', async (c) => c.json(await fundOverview(c.env.DB, c.get('user'))));

// ---------------------------------------------------------------- contribution periods
money.post('/contribution-periods', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const db = c.env.DB;
  const b = parse(await readJson(c), {
    title: v.string({ min: 2, max: 60 }),
    amountPerMember: v.money({ min: 0 }),
    dueDate: v.date({ optional: true }),
    memberIds: v.array(v.id(), { max: 50, optional: true }),
  });
  const ids = b.memberIds?.length ? b.memberIds : (await activeMembers(db)).map((m) => m.id);
  await memberIdsCheck(db, ids);
  const now = nowIso();
  const r = await run(
    db,
    'INSERT INTO contribution_periods (title, amount_per_member, due_date, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    b.title,
    b.amountPerMember,
    b.dueDate,
    me.id,
    now,
    now,
  );
  const periodId = r.meta.last_row_id;
  for (const id of new Set(ids)) {
    await run(db, 'INSERT INTO contributions (period_id, user_id, amount_due) VALUES (?, ?, ?)', periodId, id, b.amountPerMember);
  }
  await logActivity(db, 'contribution_period', periodId, me.id, 'created');
  await notify(fromRequest(c), [...ids].filter((id) => id !== me.id), {
    type: 'contribution_due',
    title: `مساهمة الصندوق: ${b.title}`,
    body: `حصتك ${formatMoney(b.amountPerMember)}`,
    link: '/money',
  });
  return c.json(await fundOverview(db, me), 201);
});

money.patch('/contribution-periods/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const id = parseId(c.req.param('id'));
  const p = await first(c.env.DB, 'SELECT * FROM contribution_periods WHERE id = ? AND deleted_at IS NULL', id);
  if (!p) throw notFound();
  const b = parse(await readJson(c), { title: v.string({ min: 2, max: 60 }), dueDate: v.date({ optional: true }) }, { partial: true });
  await run(
    c.env.DB,
    'UPDATE contribution_periods SET title = ?, due_date = ?, updated_at = ? WHERE id = ?',
    b.title ?? p.title,
    b.dueDate !== undefined ? b.dueDate : p.due_date,
    nowIso(),
    id,
  );
  return c.json(await fundOverview(c.env.DB, me));
});

money.delete('/contribution-periods/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const id = parseId(c.req.param('id'));
  await run(c.env.DB, 'UPDATE contribution_periods SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL', nowIso(), id);
  await logActivity(c.env.DB, 'contribution_period', id, me.id, 'deleted');
  return c.json({ ok: true });
});

money.post('/contribution-periods/:id/restore', async (c) => {
  assertManager(c.get('user'));
  await run(c.env.DB, 'UPDATE contribution_periods SET deleted_at = NULL WHERE id = ?', parseId(c.req.param('id')));
  return c.json({ ok: true });
});

async function loadContribution(db, id) {
  const row = await first(
    db,
    `SELECT c.*, cp.title AS period_title FROM contributions c JOIN contribution_periods cp ON cp.id = c.period_id
     WHERE c.id = ? AND cp.deleted_at IS NULL`,
    id,
  );
  if (!row) throw notFound();
  return row;
}

money.patch('/contributions/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadContribution(c.env.DB, parseId(c.req.param('id')));
  const b = parse(await readJson(c), { amountDue: v.money({ min: 0 }) });
  await run(c.env.DB, 'UPDATE contributions SET amount_due = ? WHERE id = ?', b.amountDue, row.id);
  await logActivity(c.env.DB, 'contribution', row.id, me.id, 'updated', b);
  return c.json(await fundOverview(c.env.DB, me));
});

money.post('/contributions/:id/payments', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadContribution(c.env.DB, parseId(c.req.param('id')));
  const b = parse(await readJson(c), { amount: v.money(), date: v.date({ optional: true }), note: v.string({ max: 200, optional: true }) });
  await run(
    c.env.DB,
    'INSERT INTO contribution_payments (contribution_id, amount, date, note, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    row.id,
    b.amount,
    b.date || adenDate(),
    b.note,
    me.id,
    nowIso(),
  );
  await logActivity(c.env.DB, 'contribution', row.id, me.id, 'payment', { amount: b.amount });
  return c.json(await fundOverview(c.env.DB, me), 201);
});

money.get('/contributions/:id/payments', async (c) => {
  const row = await loadContribution(c.env.DB, parseId(c.req.param('id')));
  const me = c.get('user');
  if (!isManager(me) && row.user_id !== me.id) throw forbidden();
  const rows = await all(c.env.DB, 'SELECT * FROM contribution_payments WHERE contribution_id = ? AND deleted_at IS NULL ORDER BY date, id', row.id);
  return c.json({ payments: camelAll(rows) });
});

money.delete('/contribution-payments/:id', async (c) => {
  const me = c.get('user');
  assertManager(me);
  await run(c.env.DB, 'UPDATE contribution_payments SET deleted_at = ? WHERE id = ?', nowIso(), parseId(c.req.param('id')));
  return c.json(await fundOverview(c.env.DB, me));
});

money.post('/contributions/:id/remind', async (c) => {
  const me = c.get('user');
  assertManager(me);
  const row = await loadContribution(c.env.DB, parseId(c.req.param('id')));
  const paid = await first(c.env.DB, 'SELECT COALESCE(SUM(amount), 0) AS s FROM contribution_payments WHERE contribution_id = ? AND deleted_at IS NULL', row.id);
  const remaining = row.amount_due - paid.s;
  if (remaining <= 0) throw conflict('المساهمة مدفوعة بالكامل');
  await notify(fromRequest(c), [row.user_id], {
    type: 'contribution_due',
    title: 'تذكير بمساهمة الصندوق',
    body: `${row.period_title}: المتبقي ${formatMoney(remaining)}`,
    link: '/money',
  });
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- shared expenses
const expenseSchema = {
  title: v.string({ min: 2, max: 100 }),
  category: v.enum(Object.keys(EXPENSE_CATEGORIES), { defaultValue: 'other' }),
  amount: v.money(),
  date: v.date({ optional: true }),
  paidFromFund: v.bool({ defaultValue: false }),
  payerId: v.id({ optional: true }),
  splitMemberIds: v.array(v.id(), { max: 50, optional: true }),
  note: v.text({ max: 500 }),
  attachmentUrl: v.url({ optional: true }),
};

const EXPENSE_SELECT = `SELECT e.*, u.name AS payer_name, cu.name AS created_by_name
  FROM shared_expenses e LEFT JOIN users u ON u.id = e.payer_id LEFT JOIN users cu ON cu.id = e.created_by`;

async function loadExpense(db, id, { includeDeleted = false } = {}) {
  const row = await first(db, `${EXPENSE_SELECT} WHERE e.id = ? ${includeDeleted ? '' : 'AND e.deleted_at IS NULL'}`, id);
  if (!row) throw notFound('المصروف غير موجود');
  return row;
}

const canEditExpense = (me, e) => isManager(me) || e.created_by === me.id;

async function normalizeExpense(c, b, me) {
  const db = c.env.DB;
  if (b.paidFromFund && !isManager(me)) throw forbidden('الصرف من الصندوق للمدير فقط');
  let payerId = b.paidFromFund ? null : b.payerId || me.id;
  if (payerId !== me.id && !b.paidFromFund && !isManager(me)) throw forbidden('سجّل المصروفات التي دفعتها أنت فقط');
  const split = b.splitMemberIds?.length ? [...new Set(b.splitMemberIds)] : (await activeMembers(db)).map((m) => m.id);
  await memberIdsCheck(db, [...split, ...(payerId ? [payerId] : [])]);
  return { ...b, payerId, split };
}

money.get('/shared-expenses', async (c) => {
  const { from, to, category } = c.req.query();
  const where = ['e.deleted_at IS NULL'];
  const params = [];
  if (from) {
    where.push('e.date >= ?');
    params.push(from);
  }
  if (to) {
    where.push('e.date <= ?');
    params.push(to);
  }
  if (category) {
    where.push('e.category = ?');
    params.push(category);
  }
  const rows = await all(c.env.DB, `${EXPENSE_SELECT} WHERE ${where.join(' AND ')} ORDER BY e.date DESC, e.id DESC LIMIT 500`, ...params);
  return c.json({
    expenses: rows.map((r) => {
      const e = camel(r);
      return { ...e, shares: Object.fromEntries(splitAmount(e.amount, e.splitMemberIds)) };
    }),
    categories: EXPENSE_CATEGORIES,
  });
});

money.post('/shared-expenses', async (c) => {
  const me = c.get('user');
  const b = await normalizeExpense(c, parse(await readJson(c), expenseSchema), me);
  const now = nowIso();
  const r = await run(
    c.env.DB,
    `INSERT INTO shared_expenses (title, category, amount, date, paid_from_fund, payer_id, split_member_ids, note, attachment_url, created_by, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    b.title,
    b.category,
    b.amount,
    b.date || adenDate(),
    b.paidFromFund,
    b.payerId,
    JSON.stringify(b.split),
    b.note,
    b.attachmentUrl,
    me.id,
    now,
    now,
  );
  await logActivity(c.env.DB, 'shared_expense', r.meta.last_row_id, me.id, 'created');
  return c.json({ expense: camel(await loadExpense(c.env.DB, r.meta.last_row_id)) }, 201);
});

money.patch('/shared-expenses/:id', async (c) => {
  const me = c.get('user');
  const row = await loadExpense(c.env.DB, parseId(c.req.param('id')));
  if (!canEditExpense(me, row)) throw forbidden('يعدّل المصروف من أضافه أو المدير');
  const patch = parse(await readJson(c), expenseSchema, { partial: true });
  const current = camel(row);
  const merged = {
    title: patch.title ?? current.title,
    category: patch.category ?? current.category,
    amount: patch.amount ?? current.amount,
    date: patch.date ?? current.date,
    paidFromFund: patch.paidFromFund ?? current.paidFromFund,
    payerId: patch.payerId !== undefined ? patch.payerId : current.payerId,
    splitMemberIds: patch.splitMemberIds ?? current.splitMemberIds,
    note: patch.note !== undefined ? patch.note : current.note,
    attachmentUrl: patch.attachmentUrl !== undefined ? patch.attachmentUrl : current.attachmentUrl,
  };
  if (!isManager(me) && merged.payerId === null && !merged.paidFromFund) merged.payerId = me.id;
  const b = await normalizeExpense(c, merged, me);
  await run(
    c.env.DB,
    `UPDATE shared_expenses SET title = ?, category = ?, amount = ?, date = ?, paid_from_fund = ?, payer_id = ?, split_member_ids = ?, note = ?, attachment_url = ?, updated_at = ? WHERE id = ?`,
    b.title,
    b.category,
    b.amount,
    b.date,
    b.paidFromFund,
    b.payerId,
    JSON.stringify(b.split),
    b.note,
    b.attachmentUrl,
    nowIso(),
    row.id,
  );
  await logActivity(c.env.DB, 'shared_expense', row.id, me.id, 'updated', patch);
  return c.json({ expense: camel(await loadExpense(c.env.DB, row.id)) });
});

money.post('/shared-expenses/:id/copy', async (c) => {
  const me = c.get('user');
  const row = camel(await loadExpense(c.env.DB, parseId(c.req.param('id'))));
  if (row.paidFromFund && !isManager(me)) throw forbidden();
  const b = await normalizeExpense(c, { ...row, payerId: row.paidFromFund ? null : isManager(me) ? row.payerId : me.id, date: adenDate() }, me);
  const now = nowIso();
  const r = await run(
    c.env.DB,
    `INSERT INTO shared_expenses (title, category, amount, date, paid_from_fund, payer_id, split_member_ids, note, attachment_url, created_by, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    b.title,
    b.category,
    b.amount,
    b.date,
    b.paidFromFund,
    b.payerId,
    JSON.stringify(b.split),
    b.note,
    b.attachmentUrl,
    me.id,
    now,
    now,
  );
  return c.json({ expense: camel(await loadExpense(c.env.DB, r.meta.last_row_id)) }, 201);
});

money.delete('/shared-expenses/:id', async (c) => {
  const me = c.get('user');
  const row = await loadExpense(c.env.DB, parseId(c.req.param('id')));
  if (!canEditExpense(me, row)) throw forbidden('يحذف المصروف من أضافه أو المدير');
  await run(c.env.DB, 'UPDATE shared_expenses SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), row.id);
  await logActivity(c.env.DB, 'shared_expense', row.id, me.id, 'deleted');
  return c.json({ ok: true });
});

money.post('/shared-expenses/:id/restore', async (c) => {
  const me = c.get('user');
  const row = await loadExpense(c.env.DB, parseId(c.req.param('id')), { includeDeleted: true });
  if (!canEditExpense(me, row)) throw forbidden();
  await run(c.env.DB, 'UPDATE shared_expenses SET deleted_at = NULL WHERE id = ?', row.id);
  return c.json({ expense: camel(await loadExpense(c.env.DB, row.id)) });
});

// ---------------------------------------------------------------- settlements
money.post('/settlements', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), {
    fromUserId: v.id({ optional: true }),
    toUserId: v.id(),
    amount: v.money(),
    date: v.date({ optional: true }),
    note: v.string({ max: 200, optional: true }),
  });
  const fromId = b.fromUserId || me.id;
  if (fromId !== me.id && b.toUserId !== me.id && !isManager(me)) throw forbidden('سجّل التسويات التي أنت طرف فيها');
  if (fromId === b.toUserId) throw badRequest('اختر طرفين مختلفين');
  await memberIdsCheck(c.env.DB, [fromId, b.toUserId]);
  await run(
    c.env.DB,
    'INSERT INTO settlements (from_user_id, to_user_id, amount, date, note, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    fromId,
    b.toUserId,
    b.amount,
    b.date || adenDate(),
    b.note,
    me.id,
    nowIso(),
  );
  return c.json(await fundOverview(c.env.DB, me), 201);
});

money.get('/settlements', async (c) => {
  const rows = await all(
    c.env.DB,
    `SELECT s.*, f.name AS from_name, t.name AS to_name FROM settlements s
     JOIN users f ON f.id = s.from_user_id JOIN users t ON t.id = s.to_user_id
     WHERE s.deleted_at IS NULL ORDER BY s.date DESC, s.id DESC LIMIT 200`,
  );
  return c.json({ settlements: camelAll(rows) });
});

money.delete('/settlements/:id', async (c) => {
  const me = c.get('user');
  const s = await first(c.env.DB, 'SELECT * FROM settlements WHERE id = ? AND deleted_at IS NULL', parseId(c.req.param('id')));
  if (!s) throw notFound();
  if (!isManager(me) && s.created_by !== me.id) throw forbidden();
  await run(c.env.DB, 'UPDATE settlements SET deleted_at = ? WHERE id = ?', nowIso(), s.id);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- debts between members
const DEBT_SELECT = `SELECT d.*, cu.name AS creditor_name, du.name AS debtor_name,
    COALESCE((SELECT SUM(amount) FROM debt_payments p WHERE p.debt_id = d.id), 0) AS paid
  FROM debts d JOIN users cu ON cu.id = d.creditor_id JOIN users du ON du.id = d.debtor_id`;

const involved = (me, d) => d.creditor_id === me.id || d.debtor_id === me.id;

async function loadDebt(db, id, me, { includeDeleted = false } = {}) {
  const d = await first(db, `${DEBT_SELECT} WHERE d.id = ? ${includeDeleted ? '' : 'AND d.deleted_at IS NULL'}`, id);
  if (!d || (!involved(me, d) && !isManager(me))) throw notFound('الدين غير موجود');
  return d;
}

const serializeDebt = (d) => ({ ...camel(d), remaining: Math.max(0, d.amount - d.paid) });

money.get('/debts', async (c) => {
  const me = c.get('user');
  const everyone = c.req.query('all') === '1' && isManager(me);
  const archived = c.req.query('archived') === '1';
  const rows = await all(
    c.env.DB,
    `${DEBT_SELECT} WHERE d.deleted_at IS NULL AND d.archived_at IS ${archived ? 'NOT NULL' : 'NULL'}
     ${everyone ? '' : 'AND (d.creditor_id = ? OR d.debtor_id = ?)'} ORDER BY d.settled_at IS NOT NULL, d.due_date IS NULL, d.due_date, d.id DESC`,
    ...(everyone ? [] : [me.id, me.id]),
  );
  return c.json({ debts: rows.map(serializeDebt) });
});

money.post('/debts', async (c) => {
  const me = c.get('user');
  const b = parse(await readJson(c), {
    otherUserId: v.id(),
    direction: v.enum(['owe', 'owed']),
    amount: v.money(),
    title: v.string({ max: 100, optional: true }),
    dueDate: v.date({ optional: true }),
    note: v.text({ max: 500 }),
  });
  if (b.otherUserId === me.id) throw badRequest('اختر زميلاً آخر', { otherUserId: 'اختر زميلاً آخر' });
  await memberIdsCheck(c.env.DB, [b.otherUserId]);
  const [creditor, debtor] = b.direction === 'owed' ? [me.id, b.otherUserId] : [b.otherUserId, me.id];
  const now = nowIso();
  const r = await run(
    c.env.DB,
    'INSERT INTO debts (creditor_id, debtor_id, title, amount, due_date, note, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    creditor,
    debtor,
    b.title,
    b.amount,
    b.dueDate,
    b.note,
    me.id,
    now,
    now,
  );
  await logActivity(c.env.DB, 'debt', r.meta.last_row_id, me.id, 'created');
  return c.json({ debt: serializeDebt(await loadDebt(c.env.DB, r.meta.last_row_id, me)) }, 201);
});

money.patch('/debts/:id', async (c) => {
  const me = c.get('user');
  const d = await loadDebt(c.env.DB, parseId(c.req.param('id')), me);
  if (d.created_by !== me.id && !isManager(me)) throw forbidden('يعدّل الدين من سجّله');
  const b = parse(
    await readJson(c),
    { amount: v.money(), title: v.string({ max: 100, optional: true }), dueDate: v.date({ optional: true }), note: v.text({ max: 500 }) },
    { partial: true },
  );
  const amount = b.amount ?? d.amount;
  if (amount < d.paid) throw badRequest('المبلغ أقل من المسدَّد', { amount: 'المبلغ أقل من المسدَّد' });
  await run(
    c.env.DB,
    'UPDATE debts SET amount = ?, title = ?, due_date = ?, note = ?, settled_at = ?, updated_at = ? WHERE id = ?',
    amount,
    b.title !== undefined ? b.title : d.title,
    b.dueDate !== undefined ? b.dueDate : d.due_date,
    b.note !== undefined ? b.note : d.note,
    amount <= d.paid ? d.settled_at || nowIso() : null,
    nowIso(),
    d.id,
  );
  return c.json({ debt: serializeDebt(await loadDebt(c.env.DB, d.id, me)) });
});

money.post('/debts/:id/payments', async (c) => {
  const me = c.get('user');
  const db = c.env.DB;
  const d = await loadDebt(db, parseId(c.req.param('id')), me);
  const b = parse(await readJson(c), { amount: v.money(), date: v.date({ optional: true }), note: v.string({ max: 200, optional: true }) });
  const remaining = debtRemaining({ id: d.id, amount: d.amount }, [{ debtId: d.id, amount: d.paid }]);
  if (remaining <= 0) throw conflict('الدين مسدَّد بالكامل');
  if (b.amount > remaining) throw badRequest(`المتبقي ${formatMoney(remaining)} فقط`, { amount: `المتبقي ${formatMoney(remaining)} فقط` });
  await run(db, 'INSERT INTO debt_payments (debt_id, amount, date, note, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)', d.id, b.amount, b.date || adenDate(), b.note, me.id, nowIso());
  if (b.amount === remaining) await run(db, 'UPDATE debts SET settled_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), d.id);
  await logActivity(db, 'debt', d.id, me.id, 'payment', { amount: b.amount });
  const other = me.id === d.creditor_id ? d.debtor_id : d.creditor_id;
  await notify(fromRequest(c), [other], {
    type: 'debt_payment',
    title: 'تسديد دين',
    body: `${me.name} سجّل دفعة ${formatMoney(b.amount)}${d.title ? ` — ${d.title}` : ''}`,
    link: '/money?tab=debts',
  });
  return c.json({ debt: serializeDebt(await loadDebt(db, d.id, me)) }, 201);
});

money.get('/debts/:id/payments', async (c) => {
  const me = c.get('user');
  const d = await loadDebt(c.env.DB, parseId(c.req.param('id')), me);
  const rows = await all(c.env.DB, 'SELECT * FROM debt_payments WHERE debt_id = ? ORDER BY date, id', d.id);
  return c.json({ payments: camelAll(rows) });
});

for (const [path, column, value] of [
  ['archive', 'archived_at', true],
  ['unarchive', 'archived_at', false],
  ['restore', 'deleted_at', false],
]) {
  money.post(`/debts/:id/${path}`, async (c) => {
    const me = c.get('user');
    const d = await loadDebt(c.env.DB, parseId(c.req.param('id')), me, { includeDeleted: path === 'restore' });
    if (d.created_by !== me.id && !isManager(me) && path === 'restore') throw forbidden();
    await run(c.env.DB, `UPDATE debts SET ${column} = ?, updated_at = ? WHERE id = ?`, value ? nowIso() : null, nowIso(), d.id);
    return c.json({ debt: serializeDebt(await loadDebt(c.env.DB, d.id, me)) });
  });
}

money.delete('/debts/:id', async (c) => {
  const me = c.get('user');
  const d = await loadDebt(c.env.DB, parseId(c.req.param('id')), me);
  if (d.created_by !== me.id && !isManager(me)) throw forbidden('يحذف الدين من سجّله');
  await run(c.env.DB, 'UPDATE debts SET deleted_at = ?, updated_at = ? WHERE id = ?', nowIso(), nowIso(), d.id);
  await logActivity(c.env.DB, 'debt', d.id, me.id, 'deleted');
  return c.json({ ok: true });
});

export default money;
