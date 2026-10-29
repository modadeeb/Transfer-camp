// Personal weekly budget (same rule as «حياتي»):
//   remaining     = income + carriedIn − essentials
//   allowed today = (remaining − spent on earlier days) ÷ days left including today
// Always computed, never stored, so savings/overspend/extra income spread over the remaining days.
import { addDays, diffDays, weekDates } from './dates.js';

export function weekEnd(startDate) {
  return weekDates(startDate)[6];
}

/**
 * @param {object} p
 * @param {{startDate:string,endDate:string,carriedIn:number}} p.week
 * @param {Array<{amount:number}>} p.incomes
 * @param {Array<{amount:number}>} p.essentials
 * @param {Array<{date:string,amount:number}>} p.expenses
 * @param {string} p.today
 */
export function budgetSummary({ week, incomes = [], essentials = [], expenses = [], today }) {
  const sum = (list) => list.reduce((s, x) => s + Number(x.amount || 0), 0);
  const totalIncome = sum(incomes) + Number(week.carriedIn || 0);
  const essentialsTotal = sum(essentials);
  const remaining = totalIncome - essentialsTotal;

  const start = week.startDate;
  const end = week.endDate;
  const effectiveToday = today < start ? start : today;
  const spentBefore = sum(expenses.filter((e) => e.date < effectiveToday));
  const spentToday = sum(expenses.filter((e) => e.date === effectiveToday));
  const spentTotal = sum(expenses);
  const daysLeft = effectiveToday > end ? 0 : diffDays(effectiveToday, end) + 1;

  const allowedToday = daysLeft > 0 ? Math.floor((remaining - spentBefore) / daysLeft) : 0;
  const leftToday = allowedToday - spentToday;
  const futureDays = Math.max(0, daysLeft - 1);
  const perFutureDay = futureDays > 0 ? Math.floor((remaining - spentBefore - spentToday) / futureDays) : 0;

  const days = [];
  for (let i = 0; i <= diffDays(start, end); i += 1) {
    const date = addDays(start, i);
    const spent = sum(expenses.filter((e) => e.date === date));
    let allowed = null;
    if (date === effectiveToday && daysLeft > 0) allowed = allowedToday;
    else if (date > effectiveToday && date <= end) allowed = perFutureDay;
    days.push({ date, spent, allowed, past: date < effectiveToday });
  }

  return {
    totalIncome,
    essentialsTotal,
    remaining,
    spentBefore,
    spentToday,
    spentTotal,
    left: remaining - spentTotal,
    daysLeft,
    allowedToday,
    leftToday,
    overToday: leftToday < 0 ? -leftToday : 0,
    days,
  };
}

/** What allowedToday becomes if an extra expense/income is added today (for live previews). */
export function previewAllowance(input, { addExpense = 0, addIncome = 0 }) {
  const before = budgetSummary(input);
  const after = budgetSummary({
    ...input,
    incomes: [...(input.incomes || []), { amount: addIncome }],
    expenses: [...(input.expenses || []), { date: input.today, amount: addExpense }],
  });
  return { before, after };
}
