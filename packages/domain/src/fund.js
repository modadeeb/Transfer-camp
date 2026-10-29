// Shared fund, member balances, debts between members and settlement.
// All amounts are whole Yemeni rials.

/** Split an amount equally; the remainder goes one rial at a time to the first members. */
export function splitAmount(amount, memberIds) {
  const ids = [...memberIds];
  const n = ids.length;
  const shares = new Map();
  if (!n) return shares;
  const base = Math.floor(amount / n);
  let rest = amount - base * n;
  for (const id of ids) {
    shares.set(id, base + (rest > 0 ? 1 : 0));
    if (rest > 0) rest -= 1;
  }
  return shares;
}

export function debtRemaining(debt, payments = []) {
  const paid = payments.filter((p) => p.debtId === debt.id).reduce((s, p) => s + p.amount, 0);
  return Math.max(0, debt.amount - paid);
}

/**
 * Net position of every member (positive = others owe them).
 *  - expenses paid personally by a member: payer +amount, each participant -share
 *  - expenses paid from the fund don't create member balances (covered by contributions)
 *  - debts between members: creditor +remaining, debtor -remaining
 *  - settlements (A pays B): A +amount, B -amount
 */
export function memberNets({ memberIds, expenses = [], debts = [], debtPayments = [], settlements = [] }) {
  const nets = new Map(memberIds.map((id) => [id, 0]));
  const add = (id, v) => {
    if (nets.has(id)) nets.set(id, nets.get(id) + v);
  };
  for (const e of expenses) {
    if (e.deletedAt || e.paidFromFund || e.payerId == null) continue;
    add(e.payerId, e.amount);
    for (const [id, share] of splitAmount(e.amount, e.splitMemberIds)) add(id, -share);
  }
  for (const d of debts) {
    if (d.deletedAt) continue;
    const rem = debtRemaining(d, debtPayments);
    add(d.creditorId, rem);
    add(d.debtorId, -rem);
  }
  for (const s of settlements) {
    if (s.deletedAt) continue;
    add(s.fromId, s.amount);
    add(s.toId, -s.amount);
  }
  return nets;
}

/** Fewest transfers (greedy: largest debtor pays largest creditor). */
export function settlementPlan(nets) {
  const creditors = [];
  const debtors = [];
  for (const [id, v] of nets) {
    if (v > 0) creditors.push({ id, v });
    else if (v < 0) debtors.push({ id, v: -v });
  }
  const order = (a, b) => b.v - a.v || String(a.id).localeCompare(String(b.id));
  const transfers = [];
  while (creditors.length && debtors.length) {
    creditors.sort(order);
    debtors.sort(order);
    const c = creditors[0];
    const d = debtors[0];
    const amount = Math.min(c.v, d.v);
    transfers.push({ fromId: d.id, toId: c.id, amount });
    c.v -= amount;
    d.v -= amount;
    if (c.v === 0) creditors.shift();
    if (d.v === 0) debtors.shift();
  }
  return transfers;
}

/** Fund cash = contributions paid − expenses paid from the fund. */
export function fundBalance({ contributionPayments = [], expenses = [] }) {
  const inflow = contributionPayments.filter((p) => !p.deletedAt).reduce((s, p) => s + p.amount, 0);
  const outflow = expenses
    .filter((e) => !e.deletedAt && e.paidFromFund)
    .reduce((s, e) => s + e.amount, 0);
  return { inflow, outflow, balance: inflow - outflow };
}

/** Contribution status for one member in one period. */
export function contributionStatus({ amountDue, paid, dueDate, today }) {
  const remaining = Math.max(0, amountDue - paid);
  if (remaining === 0) return { remaining, status: 'paid' };
  if (dueDate && dueDate < today) return { remaining, status: 'overdue' };
  return { remaining, status: paid > 0 ? 'partial' : 'due' };
}
