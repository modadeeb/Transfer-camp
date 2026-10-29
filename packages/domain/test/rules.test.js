import { describe, expect, it } from 'vitest';
import {
  adenDate,
  adenTime,
  adenToInstant,
  budgetSummary,
  contributionStatus,
  currentStreak,
  debtRemaining,
  fairnessReport,
  formatMoney,
  formatTime,
  fundBalance,
  isDate,
  isOverdue,
  memberNets,
  nextOccurrence,
  nextStatus,
  previewAllowance,
  settlementPlan,
  sleepMinutes,
  splitAmount,
  suggestAssignees,
  TransitionError,
  weekDots,
} from '../src/index.js';

describe('dates (Aden)', () => {
  it('converts instants to Aden date/time', () => {
    const t = new Date('2026-10-29T22:30:00Z');
    expect(adenDate(t)).toBe('2026-10-30');
    expect(adenTime(t)).toBe('01:30');
    expect(adenToInstant('2026-10-30', '01:30').toISOString()).toBe('2026-10-29T22:30:00.000Z');
  });
  it('validates dates', () => {
    expect(isDate('2026-02-29')).toBe(false);
    expect(isDate('2028-02-29')).toBe(true);
    expect(isDate('2026-1-01')).toBe(false);
  });
});

describe('task lifecycle', () => {
  const company = { status: 'pending', needsApproval: true };
  const house = { status: 'pending', needsApproval: false };
  it('assignee starts and submits; company tasks wait for approval', () => {
    expect(nextStatus(company, 'start', { isAssignee: true })).toBe('in_progress');
    expect(nextStatus({ ...company, status: 'in_progress' }, 'submit', { isAssignee: true })).toBe('submitted');
    expect(nextStatus({ ...company, status: 'submitted' }, 'approve', { isManager: true })).toBe('approved');
  });
  it('house tasks without approval complete immediately', () => {
    expect(nextStatus(house, 'submit', { isAssignee: true })).toBe('approved');
    expect(nextStatus({ ...house, status: 'approved' }, 'undo', { isAssignee: true })).toBe('in_progress');
  });
  it('blocks invalid moves', () => {
    expect(() => nextStatus(company, 'start', { isAssignee: false })).toThrow(TransitionError);
    expect(() => nextStatus({ ...company, status: 'submitted' }, 'approve', { isAssignee: true })).toThrow(TransitionError);
    expect(() => nextStatus({ ...company, status: 'approved' }, 'undo', { isAssignee: true })).toThrow(TransitionError);
    expect(() => nextStatus(company, 'return', { isManager: true })).toThrow(TransitionError);
  });
  it('manager return and set', () => {
    expect(nextStatus({ ...company, status: 'submitted' }, 'return', { isManager: true })).toBe('returned');
    expect(nextStatus(company, 'set', { isManager: true, status: 'submitted' })).toBe('submitted');
    expect(() => nextStatus(company, 'set', { isManager: true, status: 'x' })).toThrow(TransitionError);
  });
  it('overdue and recurrence', () => {
    expect(isOverdue({ status: 'pending', dueDate: '2026-10-28' }, '2026-10-29')).toBe(true);
    expect(isOverdue({ status: 'approved', dueDate: '2026-10-28' }, '2026-10-29')).toBe(false);
    expect(isOverdue({ status: 'pending', dueDate: '2026-10-29', dueTime: '10:00' }, '2026-10-29', '11:00')).toBe(true);
    expect(isOverdue({ status: 'pending', dueDate: '2026-10-29' }, '2026-10-29', '23:00')).toBe(false);
    expect(nextOccurrence('2026-10-31', 'weekly')).toBe('2026-11-07');
    expect(nextOccurrence('2026-10-31', 'none')).toBeNull();
  });
});

describe('workload', () => {
  const members = [
    { id: 1, specialty: 'frontend', sortOrder: 0 },
    { id: 2, specialty: 'backend', sortOrder: 1 },
    { id: 3, specialty: 'frontend', sortOrder: 2 },
  ];
  const tasks = [
    { kind: 'company', assigneeId: 1, size: 6, status: 'in_progress' },
    { kind: 'company', assigneeId: 3, size: 2, status: 'pending' },
    { kind: 'company', assigneeId: 3, size: 9, status: 'approved' },
    { kind: 'house', assigneeId: 3, size: 4, status: 'pending' },
  ];
  it('prefers matching specialty with the least open hours', () => {
    const s = suggestAssignees({ members, tasks, specialty: 'frontend' });
    expect(s.map((x) => x.userId)).toEqual([3, 1]);
    expect(s[0].openHours).toBe(2);
  });
  it('falls back to everyone when nobody has the specialty', () => {
    const s = suggestAssignees({ members, tasks, specialty: 'design' });
    expect(s.map((x) => x.userId)).toEqual([2, 3, 1]);
  });
  it('fairness report', () => {
    const r = fairnessReport({
      members,
      today: '2026-11-02',
      from: '2026-10-31',
      to: '2026-11-06',
      tasks: [
        { kind: 'house', assigneeId: 1, size: 3, status: 'approved', dueDate: '2026-10-31' },
        { kind: 'house', assigneeId: 1, size: 2, status: 'pending', dueDate: '2026-11-01' },
        { kind: 'company', assigneeId: 1, size: 5, status: 'pending', dueDate: '2026-11-05' },
        { kind: 'personal', assigneeId: 1, size: 9, status: 'pending', dueDate: '2026-11-01' },
      ],
    });
    const m1 = r.find((x) => x.userId === 1);
    expect(m1).toMatchObject({ housePoints: 5, houseDonePoints: 3, companyHours: 5, dueCount: 2, doneCount: 1, overdue: 1, completion: 50 });
    expect(r.find((x) => x.userId === 2).completion).toBeNull();
  });
});

describe('fund', () => {
  it('splits with remainder to the first members', () => {
    expect([...splitAmount(100, [1, 2, 3]).values()]).toEqual([34, 33, 33]);
    expect([...splitAmount(24000, [1, 2, 3, 4, 5, 6, 7, 8]).values()]).toEqual(Array(8).fill(3000));
  });
  it('member nets, debts, settlements and plan', () => {
    const memberIds = [1, 2, 3];
    const nets = memberNets({
      memberIds,
      expenses: [
        { payerId: 1, amount: 9000, splitMemberIds: [1, 2, 3] },
        { paidFromFund: true, amount: 5000, splitMemberIds: [1, 2, 3] },
        { payerId: 2, amount: 3000, splitMemberIds: [2, 3], deletedAt: '2026-10-01' },
      ],
      debts: [{ id: 7, creditorId: 3, debtorId: 2, amount: 4000 }],
      debtPayments: [{ debtId: 7, amount: 1000 }],
      settlements: [{ fromId: 2, toId: 1, amount: 1000 }],
    });
    expect(Object.fromEntries(nets)).toEqual({ 1: 5000, 2: -5000, 3: 0 });
    expect(settlementPlan(nets)).toEqual([{ fromId: 2, toId: 1, amount: 5000 }]);
    const sum = [...nets.values()].reduce((a, b) => a + b, 0);
    expect(sum).toBe(0);
  });
  it('settlement plan settles everyone with few transfers', () => {
    const nets = new Map([[1, 7000], [2, -2000], [3, -3000], [4, -2000], [5, 0]]);
    const plan = settlementPlan(nets);
    expect(plan.length).toBe(3);
    const after = new Map(nets);
    for (const t of plan) {
      after.set(t.fromId, after.get(t.fromId) + t.amount);
      after.set(t.toId, after.get(t.toId) - t.amount);
    }
    expect([...after.values()].every((v) => v === 0)).toBe(true);
  });
  it('fund balance and contribution status', () => {
    expect(
      fundBalance({
        contributionPayments: [{ amount: 30000 }, { amount: 20000 }],
        expenses: [{ paidFromFund: true, amount: 16000 }, { paidFromFund: false, amount: 999 }],
      }),
    ).toEqual({ inflow: 50000, outflow: 16000, balance: 34000 });
    expect(contributionStatus({ amountDue: 30000, paid: 30000, dueDate: '2026-11-05', today: '2026-11-10' }).status).toBe('paid');
    expect(contributionStatus({ amountDue: 30000, paid: 10000, dueDate: '2026-11-05', today: '2026-11-10' })).toEqual({ remaining: 20000, status: 'overdue' });
    expect(contributionStatus({ amountDue: 30000, paid: 10000, dueDate: '2026-11-05', today: '2026-11-01' }).status).toBe('partial');
    expect(debtRemaining({ id: 1, amount: 500 }, [{ debtId: 1, amount: 700 }])).toBe(0);
  });
});

describe('personal budget', () => {
  const week = { startDate: '2026-10-31', endDate: '2026-11-06', carriedIn: 0 };
  const incomes = [{ amount: 70000 }];
  const essentials = [{ amount: 21000 }];
  it('70,000 − 21,000 = 49,000 ÷ 7 = 7,000 a day', () => {
    const s = budgetSummary({ week, incomes, essentials, expenses: [], today: '2026-10-31' });
    expect(s.remaining).toBe(49000);
    expect(s.allowedToday).toBe(7000);
    expect(s.daysLeft).toBe(7);
  });
  it('spreads savings and overspending over the remaining days', () => {
    const expenses = [{ date: '2026-10-31', amount: 3500 }];
    const today = budgetSummary({ week, incomes, essentials, expenses, today: '2026-10-31' });
    expect(today.leftToday).toBe(3500);
    const next = budgetSummary({ week, incomes, essentials, expenses, today: '2026-11-01' });
    expect(next.allowedToday).toBe(Math.floor(45500 / 6));
    const over = budgetSummary({ week, incomes, essentials, expenses: [{ date: '2026-10-31', amount: 10000 }], today: '2026-10-31' });
    expect(over.overToday).toBe(3000);
    expect(over.days[1].allowed).toBe(Math.floor(39000 / 6));
  });
  it('extra income raises today’s allowance', () => {
    const { before, after } = previewAllowance({ week, incomes, essentials, expenses: [], today: '2026-11-04' }, { addIncome: 9000 });
    expect(before.allowedToday).toBe(Math.floor(49000 / 3));
    expect(after.allowedToday).toBe(Math.floor(58000 / 3));
  });
  it('after the week ends nothing is allowed', () => {
    expect(budgetSummary({ week, incomes, essentials, expenses: [], today: '2026-11-08' }).allowedToday).toBe(0);
  });
});

describe('streaks and sleep', () => {
  it('days not due never break the streak; today not done yet does not break it', () => {
    const habit = { days: [6, 1, 3] }; // Sat, Mon, Wed
    const done = ['2026-10-24', '2026-10-26', '2026-10-28', '2026-10-31'];
    expect(currentStreak(habit, done, '2026-11-02')).toBe(4); // Mon 2 Nov not done yet
    expect(currentStreak(habit, done.slice(1), '2026-10-31')).toBe(3);
    expect(currentStreak({ days: 'daily' }, ['2026-10-30'], '2026-10-31')).toBe(1);
    expect(currentStreak({ days: 'daily' }, ['2026-10-29'], '2026-10-31')).toBe(0);
  });
  it('week dots', () => {
    const dots = weekDots({ days: 'daily' }, ['2026-11-01'], '2026-10-31');
    expect(dots).toHaveLength(7);
    expect(dots[1]).toEqual({ date: '2026-11-01', due: true, done: true });
  });
  it('sleep across midnight', () => {
    expect(sleepMinutes('23:30', '06:00')).toBe(390);
    expect(sleepMinutes('01:00', '07:15')).toBe(375);
  });
});

describe('format', () => {
  it('money and time', () => {
    expect(formatMoney(1234567)).toBe('1,234,567 ر.ي');
    expect(formatMoney(-500, { unit: false })).toBe('−500');
    expect(formatTime('14:05')).toBe('2:05 م');
    expect(formatTime('00:30')).toBe('12:30 ص');
  });
});
