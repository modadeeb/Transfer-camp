import { describe, expect, it } from 'vitest';
import { addDays, dayOfWeek, generateDistribution, isAvailable, settleBalances, weekStartOf } from '../src/index.js';

const WEEK = '2026-10-31'; // Saturday
const members = Array.from({ length: 8 }, (_, i) => ({ id: i + 1, sortOrder: i, busy: [] }));
const chores = [
  { id: 'cook', points: 3, frequency: 'daily', slot: 'evening', peopleCount: 2 },
  { id: 'dishes', points: 2, frequency: 'daily', slot: 'evening' },
  { id: 'trash', points: 1, frequency: 'daily', slot: 'any' },
  { id: 'bath', points: 4, frequency: 'weekly', weeklyDay: 2, slot: 'morning' },
  { id: 'kitchen', points: 3, frequency: 'days', days: [6, 2], slot: 'any' },
  { id: 'shop', points: 2, frequency: 'days', days: [6, 3], slot: 'afternoon' },
];
const spread = (summary) => Math.max(...summary.map((s) => s.points)) - Math.min(...summary.map((s) => s.points));

describe('generateDistribution', () => {
  it('Saturday is the week start', () => {
    expect(dayOfWeek(WEEK)).toBe(6);
    expect(weekStartOf('2026-11-04')).toBe(WEEK);
  });

  it('expands every occurrence with the right number of people', () => {
    const r = generateDistribution({ weekStart: WEEK, members, chores });
    const count = (id) => r.items.filter((i) => i.choreId === id).length;
    expect(count('cook')).toBe(14);
    expect(count('dishes')).toBe(7);
    expect(count('trash')).toBe(7);
    expect(count('bath')).toBe(1);
    expect(count('kitchen')).toBe(2);
    expect(count('shop')).toBe(2);
    expect(r.unassigned).toBe(0);
    const bath = r.items.find((i) => i.choreId === 'bath');
    expect(dayOfWeek(bath.date)).toBe(2);
  });

  it('never puts the same person twice on one occurrence', () => {
    const r = generateDistribution({ weekStart: WEEK, members, chores });
    const byOcc = new Map();
    for (const i of r.items) {
      const k = `${i.choreId}|${i.date}`;
      byOcc.set(k, [...(byOcc.get(k) || []), i.userId]);
    }
    for (const ids of byOcc.values()) expect(new Set(ids).size).toBe(ids.length);
  });

  it('keeps weekly points close (spread ≤ heaviest chore + tolerance)', () => {
    const r = generateDistribution({ weekStart: WEEK, members, chores });
    const total = r.summary.reduce((s, x) => s + x.points, 0);
    expect(total).toBe(42 + 14 + 7 + 4 + 6 + 4);
    expect(spread(r.summary)).toBeLessThanOrEqual(5);
  });

  it('is deterministic', () => {
    const a = generateDistribution({ weekStart: WEEK, members, chores });
    const b = generateDistribution({ weekStart: WEEK, members: [...members].reverse(), chores: [...chores].reverse() });
    expect(b).toEqual(a);
  });

  it('respects fixed busy times', () => {
    const busyMembers = members.map((m) =>
      m.id <= 3 ? { ...m, busy: [{ dow: 2, start: '08:00', end: '12:00' }, { dow: 3, start: '08:00', end: '16:00' }] } : m,
    );
    const r = generateDistribution({ weekStart: WEEK, members: busyMembers, chores });
    for (const i of r.items) {
      const m = busyMembers.find((x) => x.id === i.userId);
      expect(isAvailable(m, i.date, i.slot)).toBe(true);
    }
    const bath = r.items.find((i) => i.choreId === 'bath');
    expect(bath.userId).toBeGreaterThan(3);
    const wedShop = r.items.find((i) => i.choreId === 'shop' && dayOfWeek(i.date) === 3);
    expect(wedShop.userId).toBeGreaterThan(3);
  });

  it('respects absences', () => {
    const absences = [{ userId: 5, startDate: WEEK, endDate: addDays(WEEK, 3) }];
    const r = generateDistribution({ weekStart: WEEK, members, chores, absences });
    for (const i of r.items.filter((x) => x.userId === 5)) expect(i.date > addDays(WEEK, 3)).toBe(true);
  });

  it('leaves a slot unassigned when nobody is available', () => {
    const allBusy = members.map((m) => ({ ...m, busy: [{ dow: 2, start: '07:00', end: '13:00' }] }));
    const r = generateDistribution({ weekStart: WEEK, members: allBusy, chores });
    const bath = r.items.find((i) => i.choreId === 'bath');
    expect(bath.userId).toBeNull();
    expect(r.unassigned).toBe(1);
  });

  it('rotates a weekly chore away from last week’s person', () => {
    const only = [{ id: 'bath', points: 4, frequency: 'weekly', weeklyDay: 2, slot: 'any' }];
    const first = generateDistribution({ weekStart: WEEK, members, chores: only });
    const who = first.items[0].userId;
    const next = generateDistribution({
      weekStart: addDays(WEEK, 7),
      members,
      chores: only,
      previous: [{ choreId: 'bath', userId: who }],
    });
    expect(next.items[0].userId).not.toBe(who);
  });

  it('gives more to members with a negative balance (compensation)', () => {
    const withBalance = members.map((m) => (m.id === 8 ? { ...m, balance: -6 } : m));
    const r = generateDistribution({ weekStart: WEEK, members: withBalance, chores });
    const p8 = r.summary.find((s) => s.userId === 8).points;
    const others = r.summary.filter((s) => s.userId !== 8).map((s) => s.points);
    expect(p8).toBeGreaterThan(Math.max(...others) - 1);
  });

  it('balances stay fair over many weeks (carry-over)', () => {
    let state = members.map((m) => ({ ...m, balance: 0 }));
    let previous = [];
    const cumulative = new Map(members.map((m) => [m.id, 0]));
    for (let w = 0; w < 10; w += 1) {
      const weekStart = addDays(WEEK, 7 * w);
      const absences = w === 2 ? [{ userId: 3, startDate: weekStart, endDate: addDays(weekStart, 6) }] : [];
      const r = generateDistribution({ weekStart, members: state, chores, previous, absences });
      const settled = settleBalances(state, r.items);
      for (const s of settled) cumulative.set(s.userId, cumulative.get(s.userId) + s.assigned);
      state = state.map((m) => ({ ...m, balance: settled.find((s) => s.userId === m.id).balanceAfter }));
      previous = r.items.filter((i) => i.userId != null).map((i) => ({ choreId: i.choreId, userId: i.userId }));
    }
    const vals = [...cumulative.values()];
    expect(Math.max(...vals) - Math.min(...vals)).toBeLessThanOrEqual(5);
    for (const m of state) expect(Math.abs(m.balance)).toBeLessThanOrEqual(5);
  });
});

describe('settleBalances', () => {
  it('expected share is equal; absentees go negative', () => {
    const items = [
      { userId: 1, points: 6 },
      { userId: 2, points: 6 },
      { userId: null, points: 3 },
    ];
    const r = settleBalances([{ id: 1 }, { id: 2 }, { id: 3, balance: 1 }], items);
    expect(r.map((x) => x.expected)).toEqual([4, 4, 4]);
    expect(r.map((x) => x.balanceAfter)).toEqual([2, 2, -3]);
  });
});
