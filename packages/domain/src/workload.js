// Company workload and the fairness board.
import { inRange } from './dates.js';

export const SPECIALTIES = {
  frontend: 'واجهات',
  backend: 'خادم',
  design: 'تصميم',
  qa: 'اختبار',
  pm: 'إدارة مشاريع',
};

/**
 * Suggest assignees for a company task: members with the required specialty
 * first (if anyone has it), then lowest open hours, then member order.
 */
export function suggestAssignees({ members, tasks, specialty = null }) {
  const open = new Map(members.map((m) => [m.id, 0]));
  for (const t of tasks) {
    if (t.kind !== 'company' || t.status === 'approved' || t.deletedAt || t.archivedAt) continue;
    if (open.has(t.assigneeId)) open.set(t.assigneeId, open.get(t.assigneeId) + Number(t.size || 0));
  }
  const anyMatch = specialty && members.some((m) => m.specialty === specialty);
  return members
    .map((m, index) => ({
      userId: m.id,
      openHours: open.get(m.id),
      matches: specialty ? m.specialty === specialty : true,
      index: m.sortOrder ?? index,
    }))
    .filter((c) => !anyMatch || c.matches)
    .sort((a, b) => a.openHours - b.openHours || a.index - b.index || String(a.userId).localeCompare(String(b.userId)))
    .map(({ index, ...rest }) => rest);
}

/**
 * Per-member totals for a period.
 * Completion rate counts shared tasks that were due by `today` in the range.
 */
export function fairnessReport({ members, tasks, from, to, today }) {
  const rows = new Map(
    members.map((m) => [
      m.id,
      {
        userId: m.id,
        housePoints: 0,
        houseDonePoints: 0,
        companyHours: 0,
        companyDoneHours: 0,
        dueCount: 0,
        doneCount: 0,
        overdue: 0,
        balance: Number(m.balance || 0),
      },
    ]),
  );
  for (const t of tasks) {
    if (t.deletedAt || t.kind === 'personal' || !rows.has(t.assigneeId)) continue;
    if (!t.dueDate || !inRange(t.dueDate, from, to)) continue;
    const r = rows.get(t.assigneeId);
    const size = Number(t.size || 0);
    const done = t.status === 'approved';
    if (t.kind === 'house') {
      r.housePoints += size;
      if (done) r.houseDonePoints += size;
    } else {
      r.companyHours += size;
      if (done) r.companyDoneHours += size;
    }
    if (t.dueDate <= today) {
      r.dueCount += 1;
      if (done) r.doneCount += 1;
      else if (t.dueDate < today) r.overdue += 1;
    }
  }
  return [...rows.values()].map((r) => ({
    ...r,
    completion: r.dueCount ? Math.round((r.doneCount / r.dueCount) * 100) : null,
  }));
}
