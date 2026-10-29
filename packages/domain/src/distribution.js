// Fair weekly distribution of house chores.
//
// Rules (docs/Muaskar-spec.md §3):
//  1. Weekly points stay close between members; the difference carries over (balance).
//  2. Rotation: avoid giving the same chore to the same member two weeks in a row.
//  3. Never assign during a member's fixed busy time (university/work) or absence.
//  4. Output is a draft; the manager adjusts and publishes it.
//  5. Deterministic: same inputs -> same output.
import { addDays, dayOfWeek, inRange, timeToMinutes, weekDates } from './dates.js';

export const SLOT_WINDOWS = {
  morning: [8 * 60, 12 * 60],
  afternoon: [12 * 60, 17 * 60],
  evening: [17 * 60, 22 * 60],
  any: null,
};

export const SLOT_LABELS = { morning: 'صباحاً', afternoon: 'ظهراً', evening: 'مساءً', any: 'أي وقت' };

/** Within this many points of the lowest load, rotation preferences decide. */
export const FAIRNESS_TOLERANCE = 1;

function choreDates(chore, dates) {
  if (chore.frequency === 'daily') return dates;
  if (chore.frequency === 'days') {
    const days = new Set(chore.days || []);
    return dates.filter((d) => days.has(dayOfWeek(d)));
  }
  // weekly: once, on weeklyDay (defaults to the first day of the week)
  const wanted = chore.weeklyDay ?? dayOfWeek(dates[0]);
  return dates.filter((d) => dayOfWeek(d) === wanted);
}

export function isAvailable(member, date, slot, absences = []) {
  if (absences.some((a) => a.userId === member.id && inRange(date, a.startDate, a.endDate))) return false;
  const window = SLOT_WINDOWS[slot] ?? null;
  if (!window) return true;
  const dow = dayOfWeek(date);
  return !(member.busy || []).some((b) => {
    if (b.dow !== dow) return false;
    const s = timeToMinutes(b.start);
    const e = timeToMinutes(b.end);
    return s < window[1] && e > window[0];
  });
}

function compareIds(a, b) {
  return String(a).localeCompare(String(b), 'en', { numeric: true });
}

/**
 * @param {object} input
 * @param {string} input.weekStart  first date of the week (Saturday)
 * @param {Array}  input.members    [{ id, balance?, busy?: [{dow,start,end}], sortOrder? }]
 * @param {Array}  input.chores     [{ id, points, frequency, days?, weeklyDay?, slot?, peopleCount?, active?, sortOrder? }]
 * @param {Array}  [input.previous] last week's [{ choreId, userId }]
 * @param {Array}  [input.absences] [{ userId, startDate, endDate }]
 */
export function generateDistribution({ weekStart, members, chores, previous = [], absences = [] }) {
  const dates = weekDates(weekStart);
  const orderedMembers = [...members].sort(
    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0) || compareIds(a.id, b.id),
  );
  const lastWeek = new Set(previous.map((p) => `${p.choreId}|${p.userId}`));

  const state = new Map(
    orderedMembers.map((m, index) => [
      m.id,
      { member: m, index, balance: Number(m.balance || 0), points: 0, perChore: new Map(), perDay: new Map() },
    ]),
  );

  // Expand chores into occurrences.
  const occurrences = [];
  for (const chore of chores) {
    if (chore.active === false) continue;
    const slot = chore.slot || 'any';
    for (const date of choreDates(chore, dates)) {
      const available = orderedMembers.filter((m) => isAvailable(m, date, slot, absences));
      occurrences.push({ chore, date, slot, available, people: Math.max(1, chore.peopleCount || 1) });
    }
  }

  occurrences.sort(
    (a, b) =>
      b.chore.points - a.chore.points ||
      a.available.length - b.available.length ||
      a.date.localeCompare(b.date) ||
      (a.chore.sortOrder ?? 0) - (b.chore.sortOrder ?? 0) ||
      compareIds(a.chore.id, b.chore.id),
  );

  const items = [];
  for (const occ of occurrences) {
    const taken = new Set();
    for (let k = 0; k < occ.people; k += 1) {
      const candidates = occ.available.filter((m) => !taken.has(m.id)).map((m) => state.get(m.id));
      if (candidates.length === 0) {
        items.push({ choreId: occ.chore.id, date: occ.date, slot: occ.slot, userId: null, points: occ.chore.points });
        continue;
      }
      const load = (s) => s.balance + s.points;
      const minLoad = Math.min(...candidates.map(load));
      const pool = candidates.filter((s) => load(s) <= minLoad + FAIRNESS_TOLERANCE);
      pool.sort((a, b) => {
        const aLast = lastWeek.has(`${occ.chore.id}|${a.member.id}`) ? 1 : 0;
        const bLast = lastWeek.has(`${occ.chore.id}|${b.member.id}`) ? 1 : 0;
        return (
          aLast - bLast ||
          (a.perChore.get(occ.chore.id) || 0) - (b.perChore.get(occ.chore.id) || 0) ||
          (a.perDay.get(occ.date) || 0) - (b.perDay.get(occ.date) || 0) ||
          load(a) - load(b) ||
          a.index - b.index
        );
      });
      const chosen = pool[0];
      taken.add(chosen.member.id);
      chosen.points += occ.chore.points;
      chosen.perChore.set(occ.chore.id, (chosen.perChore.get(occ.chore.id) || 0) + 1);
      chosen.perDay.set(occ.date, (chosen.perDay.get(occ.date) || 0) + 1);
      items.push({
        choreId: occ.chore.id,
        date: occ.date,
        slot: occ.slot,
        userId: chosen.member.id,
        points: occ.chore.points,
      });
    }
  }

  items.sort(
    (a, b) => a.date.localeCompare(b.date) || compareIds(a.choreId, b.choreId) || compareIds(a.userId ?? '', b.userId ?? ''),
  );

  return {
    items,
    summary: orderedMembers.map((m) => ({ userId: m.id, points: state.get(m.id).points, balanceBefore: state.get(m.id).balance })),
    unassigned: items.filter((i) => i.userId === null).length,
  };
}

/**
 * Balances after publishing a week. Everyone's expected share is the same
 * (total / members), so a member who was absent ends negative and is
 * compensated later by receiving more.
 */
export function settleBalances(members, items) {
  const assigned = new Map(members.map((m) => [m.id, 0]));
  let total = 0;
  for (const item of items) {
    if (item.userId == null || !assigned.has(item.userId)) continue;
    assigned.set(item.userId, assigned.get(item.userId) + item.points);
    total += item.points;
  }
  const expected = members.length ? total / members.length : 0;
  return members.map((m) => {
    const before = Number(m.balance || 0);
    const pts = assigned.get(m.id);
    return {
      userId: m.id,
      assigned: pts,
      expected: Math.round(expected * 100) / 100,
      balanceBefore: before,
      balanceAfter: Math.round((before + pts - expected) * 100) / 100,
    };
  });
}

export function nextWeekStart(weekStart) {
  return addDays(weekStart, 7);
}
