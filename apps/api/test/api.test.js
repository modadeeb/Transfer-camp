import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { addDays, adenDate, adenToInstant, weekStartOf } from '@camp/domain';
import { runScheduled } from '../src/cron.js';
import { client, createEnv, seedCamp } from './helpers.js';

let env;
let mf;
let camp;
const today = adenDate();
const weekStart = weekStartOf(today);

beforeAll(async () => {
  ({ env, mf } = await createEnv());
  camp = await seedCamp(env);
});
afterAll(async () => mf?.dispose());

const m = (i) => camp.members[i];
const notificationsOf = async (c) => (await c.get('/notifications')).body.notifications;

describe('setup and auth', () => {
  it('setup runs once', async () => {
    const c = client(env);
    expect((await c.get('/setup/status')).body.needsSetup).toBe(false);
    const again = await c.post('/setup', { name: 'x y', username: 'other', password: 'password-123' });
    expect(again.status).toBe(409);
  });

  it('requires the CSRF header for writes', async () => {
    const res = await camp.manager.raw('GET', '/auth/me');
    expect(res.status).toBe(200);
    const { app } = await import('../src/index.js');
    const bad = await app.fetch(new Request('http://localhost/api/auth/login', { method: 'POST', body: '{}' }), env, { waitUntil() {} });
    expect(bad.status).toBe(403);
  });

  it('rejects wrong passwords and rate-limits', async () => {
    const c = client(env);
    for (let i = 0; i < 5; i += 1) {
      const r = await c.post('/auth/login', { username: 'nobody', password: 'wrong-pass' });
      expect(r.status).toBe(401);
    }
    const blocked = await c.post('/auth/login', { username: 'nobody', password: 'wrong-pass' });
    expect(blocked.status).toBe(429);
    // other housemates on the same connection can still sign in
    expect((await client(env).post('/auth/login', { username: 'member2', password: 'member-pass-2' })).status).toBe(200);
  });

  it('unauthenticated requests are refused', async () => {
    expect((await client(env).get('/home')).status).toBe(401);
  });

  it('password change logs out other sessions', async () => {
    const a = client(env);
    const b = client(env);
    await a.post('/auth/login', { username: 'member7', password: 'member-pass-7' });
    await b.post('/auth/login', { username: 'member7', password: 'member-pass-7' });
    const r = await a.post('/auth/password', { current: 'member-pass-7', password: 'member-pass-7b' });
    expect(r.status).toBe(200);
    expect((await a.get('/auth/me')).status).toBe(200);
    expect((await b.get('/auth/me')).status).toBe(401);
    camp.members[6].client = a;
  });

  it('validation errors come back per field in Arabic', async () => {
    const r = await camp.manager.post('/members', { name: 'ا', username: 'x' });
    expect(r.status).toBe(422);
    expect(r.body.fields.name).toBeTruthy();
    expect(r.body.fields.username).toBeTruthy();
  });
});

describe('members and roles', () => {
  it('only the manager manages members', async () => {
    expect((await m(0).client.post('/members', { name: 'زائر جديد', username: 'guest1' })).status).toBe(403);
    const list = await m(0).client.get('/members');
    expect(list.body.members).toHaveLength(8);
    expect(list.body.members[0]).not.toHaveProperty('password_hash');
  });

  it('duplicate usernames are rejected', async () => {
    const r = await camp.manager.post('/members', { name: 'مكرر', username: 'MEMBER1' });
    expect(r.status).toBe(422);
  });

  it('the manager cannot archive or demote the last manager', async () => {
    expect((await camp.manager.post(`/members/${camp.managerId}/archive`)).status).toBe(409);
    expect((await camp.manager.patch(`/members/${camp.managerId}`, { role: 'member' })).status).toBe(409);
  });

  it('archived members cannot sign in; unarchive restores access', async () => {
    const created = await camp.manager.post('/members', { name: 'مؤقت', username: 'temp1' });
    const id = created.body.member.id;
    await camp.manager.post(`/members/${id}/archive`);
    const c = client(env);
    expect((await c.post('/auth/login', { username: 'temp1', password: created.body.tempPassword })).status).toBe(403);
    await camp.manager.post(`/members/${id}/unarchive`);
    expect((await c.post('/auth/login', { username: 'temp1', password: created.body.tempPassword })).status).toBe(200);
    expect((await c.get('/auth/me')).body.user.mustChangePassword).toBe(true);
    await camp.manager.del(`/members/${id}`);
    expect((await c.get('/auth/me')).status).toBe(401);
  });

  it('members set their own fixed schedule; not others', async () => {
    const r = await m(0).client.put(`/members/${m(0).id}/slots`, {
      slots: [
        { dow: 2, startTime: '08:00', endTime: '12:00', kind: 'university' },
        { dow: 3, startTime: '08:00', endTime: '16:00', kind: 'university' },
      ],
    });
    expect(r.status).toBe(200);
    expect(r.body.slots).toHaveLength(2);
    expect((await m(1).client.put(`/members/${m(0).id}/slots`, { slots: [] })).status).toBe(403);
    const bad = await m(0).client.put(`/members/${m(0).id}/slots`, { slots: [{ dow: 1, startTime: '10:00', endTime: '09:00' }] });
    expect(bad.status).toBe(422);
  });
});

describe('house chores and fair distribution', () => {
  it('manager defines chores', async () => {
    const chores = [
      { name: 'الطبخ', icon: 'chef-hat', frequency: 'daily', points: 3, peopleCount: 2, slot: 'evening' },
      { name: 'غسل الأطباق', icon: 'utensils', frequency: 'daily', points: 2, slot: 'evening' },
      { name: 'رمي القمامة', icon: 'trash-2', frequency: 'daily', points: 1 },
      { name: 'تنظيف الحمّام', icon: 'bath', frequency: 'weekly', weeklyDay: 2, points: 4, slot: 'morning' },
      { name: 'المشتريات', icon: 'shopping-cart', frequency: 'days', days: [6, 3], points: 2, slot: 'afternoon' },
    ];
    for (const ch of chores) expect((await camp.manager.post('/chores', ch)).status).toBe(201);
    expect((await m(0).client.post('/chores', chores[0])).status).toBe(403);
    expect((await camp.manager.post('/chores', { name: 'بلا أيام', frequency: 'days', points: 2 })).status).toBe(422);
    expect((await camp.manager.post('/chores', { name: 'ثقيلة', frequency: 'daily', points: 9 })).status).toBe(422);
  });

  it('generates a fair draft, respects busy times, publishes once', async () => {
    const gen = await camp.manager.post(`/distributions/${weekStart}/generate`);
    expect(gen.status).toBe(200);
    expect(gen.body.distribution.status).toBe('draft');
    expect(gen.body.unassigned).toBe(0);
    const pts = gen.body.summary.map((s) => s.points);
    expect(Math.max(...pts) - Math.min(...pts)).toBeLessThanOrEqual(5);
    const bath = gen.body.items.find((i) => i.choreName === 'تنظيف الحمّام');
    expect(bath.userId).not.toBe(m(0).id); // member 0 has university Tuesday morning

    // manual adjustment in the draft
    const item = gen.body.items.find((i) => i.choreName === 'رمي القمامة');
    const other = camp.members.find((x) => x.id !== item.userId);
    const adj = await camp.manager.patch(`/distribution-items/${item.id}`, { userId: other.id });
    expect(adj.status).toBe(200);
    expect(adj.body.items.find((i) => i.id === item.id).userId).toBe(other.id);

    expect((await m(1).client.post(`/distributions/${weekStart}/publish`)).status).toBe(403);
    const pub = await camp.manager.post(`/distributions/${weekStart}/publish`);
    expect(pub.status).toBe(200);
    expect(pub.body.distribution.status).toBe('published');
    expect((await camp.manager.post(`/distributions/${weekStart}/publish`)).status).toBe(409);
    expect((await camp.manager.post(`/distributions/${weekStart}/generate`)).status).toBe(409);

    const houseTasks = (await m(1).client.get(`/tasks?kind=house&from=${weekStart}&to=${addDays(weekStart, 6)}`)).body.tasks;
    expect(houseTasks.length).toBe(pub.body.items.length);
    const balances = pub.body.summary.map((s) => s.balanceAfter);
    expect(Math.abs(balances.reduce((a, b) => a + b, 0))).toBeLessThan(0.1);
    const notes = await notificationsOf(m(2).client);
    expect(notes.some((n) => n.type === 'distribution')).toBe(true);
  });

  it('group schedule shows the week to every member', async () => {
    const r = await m(3).client.get(`/schedule/group?weekStart=${weekStart}`);
    expect(r.status).toBe(200);
    expect(r.body.dates).toHaveLength(7);
    expect(r.body.tasks.length).toBeGreaterThan(20);
    expect(r.body.distributionStatus).toBe('published');
  });

  it('fairness board', async () => {
    const r = await m(0).client.get('/fairness?period=week');
    expect(r.status).toBe(200);
    expect(r.body.rows).toHaveLength(8);
    expect(r.body.rows.every((row) => row.housePoints > 0)).toBe(true);
  });
});

describe('task lifecycle', () => {
  let projectId;
  let taskId;

  it('manager creates a project and a company task with checklist', async () => {
    const p = await camp.manager.post('/projects', { name: 'متجر لانا', client: 'لانا للأقمشة', deadline: addDays(today, 20) });
    expect(p.status).toBe(201);
    projectId = p.body.project.id;
    const t = await camp.manager.post('/tasks', {
      kind: 'company',
      title: 'واجهة تسجيل الدخول',
      details: 'حسب التصميم المعتمد',
      assigneeIds: [m(1).id],
      projectId,
      specialty: 'frontend',
      dueDate: addDays(today, 3),
      priority: 'urgent',
      size: 4,
      recurrence: 'weekly',
      checklist: [{ text: 'التصميم' }, { text: 'الربط' }],
    });
    expect(t.status).toBe(201);
    taskId = t.body.tasks[0].id;
    expect(t.body.tasks[0].needsApproval).toBe(true);
    expect(t.body.tasks[0].checklist).toHaveLength(2);
    const notes = await notificationsOf(m(1).client);
    expect(notes[0]).toMatchObject({ type: 'task_assigned', urgent: true, link: `/task/${taskId}` });
  });

  it('members cannot create or edit shared tasks', async () => {
    expect((await m(1).client.post('/tasks', { kind: 'company', title: 'مهمة عضو' })).status).toBe(403);
    expect((await m(1).client.patch(`/tasks/${taskId}`, { title: 'تعديل' })).status).toBe(403);
    expect((await m(1).client.del(`/tasks/${taskId}`)).status).toBe(403);
  });

  it('assignee works it; manager returns then approves; recurrence spawns next', async () => {
    const a = m(1).client;
    expect((await m(2).client.post(`/tasks/${taskId}/action`, { action: 'start' })).status).toBe(409);
    expect((await a.post(`/tasks/${taskId}/action`, { action: 'start' })).body.task.status).toBe('in_progress');
    const item = (await a.get(`/tasks/${taskId}`)).body.task.checklist[0];
    expect((await a.post(`/tasks/${taskId}/checklist`, { itemId: item.id, done: true })).body.task.checklist[0].done).toBe(true);
    const sub = await a.post(`/tasks/${taskId}/action`, { action: 'submit', note: 'جاهزة', url: 'https://example.com/pr/1' });
    expect(sub.body.task.status).toBe('submitted');
    expect((await notificationsOf(camp.manager))[0].type).toBe('task_submitted');
    expect((await a.post(`/tasks/${taskId}/action`, { action: 'approve' })).status).toBe(409);
    expect((await camp.manager.post(`/tasks/${taskId}/action`, { action: 'return' })).status).toBe(422);
    const ret = await camp.manager.post(`/tasks/${taskId}/action`, { action: 'return', note: 'عدّل الألوان' });
    expect(ret.body.task).toMatchObject({ status: 'returned', returnNote: 'عدّل الألوان' });
    expect((await notificationsOf(a))[0].type).toBe('task_returned');
    await a.post(`/tasks/${taskId}/action`, { action: 'submit' });
    const ok = await camp.manager.post(`/tasks/${taskId}/action`, { action: 'approve' });
    expect(ok.body.task.status).toBe('approved');
    expect(ok.body.nextTaskId).toBeTruthy();
    const next = (await a.get(`/tasks/${ok.body.nextTaskId}`)).body.task;
    expect(next).toMatchObject({ status: 'pending', dueDate: addDays(today, 10), title: 'واجهة تسجيل الدخول' });
    expect(next.checklist.every((i) => !i.done)).toBe(true);
    const detail = await a.get(`/tasks/${taskId}`);
    expect(detail.body.history.map((h) => h.action)).toEqual(expect.arrayContaining(['created', 'start', 'submit', 'return', 'approve']));
  });

  it('deleting an approved shared task archives it (keeps fairness); others go to trash', async () => {
    const del = await camp.manager.del(`/tasks/${taskId}`);
    expect(del.body.result).toBe('archived');
    const t = await camp.manager.post('/tasks', { kind: 'house', title: 'ترتيب الصالة', assigneeIds: [m(2).id], dueDate: today, size: 2 });
    const id = t.body.tasks[0].id;
    expect((await camp.manager.del(`/tasks/${id}`)).body.result).toBe('deleted');
    expect((await m(2).client.get(`/tasks/${id}`)).status).toBe(404);
    const trash = await camp.manager.get('/trash');
    expect(trash.body.items.some((i) => i.entity === 'task' && i.id === id)).toBe(true);
    expect((await camp.manager.post('/trash/restore', { entity: 'task', id })).status).toBe(200);
    expect((await m(2).client.get(`/tasks/${id}`)).status).toBe(200);
  });

  it('multi-assign, auto-assign by specialty, copy, bulk and reorder', async () => {
    const multi = await camp.manager.post('/tasks', { kind: 'house', title: 'تنظيف السطح', assigneeIds: [m(3).id, m(4).id], dueDate: today, size: 3 });
    expect(multi.body.tasks).toHaveLength(2);
    expect(multi.body.tasks[0].groupId).toBeTruthy();
    const auto = await camp.manager.post('/tasks', { kind: 'company', title: 'تصميم الشعار', specialty: 'design', autoAssign: true, size: 3 });
    expect(auto.body.tasks[0].assigneeId).toBe(m(2).id); // the only designer
    const copy = await camp.manager.post(`/tasks/${auto.body.tasks[0].id}/copy`);
    expect(copy.status).toBe(201);
    const ids = [...multi.body.tasks.map((t) => t.id), copy.body.task.id];
    const bulk = await camp.manager.post('/tasks/bulk', { ids, action: 'reschedule', dueDate: addDays(today, 1) });
    expect(Object.values(bulk.body.results).every((x) => x === 'rescheduled')).toBe(true);
    const reassign = await camp.manager.post('/tasks/bulk', { ids: [copy.body.task.id], action: 'reassign', assigneeId: m(5).id });
    expect(reassign.body.results[copy.body.task.id]).toBe('reassigned');
    const reversed = [...ids].reverse();
    expect((await camp.manager.post('/reorder', { entity: 'tasks', ids: reversed })).status).toBe(200);
    const listed = (await camp.manager.get(`/tasks?from=${addDays(today, 1)}&to=${addDays(today, 1)}`)).body.tasks.map((t) => t.id).filter((id) => ids.includes(id));
    expect(listed).toEqual(reversed);
    expect((await m(1).client.post('/reorder', { entity: 'tasks', ids })).status).toBe(422);
  });

  it('personal tasks are private (even from the manager)', async () => {
    const p = await m(0).client.post('/tasks', { kind: 'personal', title: 'مراجعة مادة الشبكات', dueDate: today });
    expect(p.status).toBe(201);
    const id = p.body.tasks[0].id;
    expect((await camp.manager.get(`/tasks/${id}`)).status).toBe(404);
    expect((await camp.manager.get('/tasks?kind=personal')).body.tasks.some((t) => t.id === id)).toBe(false);
    expect((await m(0).client.post(`/tasks/${id}/action`, { action: 'submit' })).body.task.status).toBe('approved');
  });
});

describe('swap requests', () => {
  it('member asks a colleague; colleague accepts; points move', async () => {
    await camp.manager.post('/tasks', { kind: 'house', title: 'تنظيف المطبخ', assigneeIds: [m(0).id], dueDate: addDays(today, 1), size: 3 });
    const mine = (await m(0).client.get(`/tasks?mine=1&kind=house&status=pending&from=${today}`)).body.tasks;
    const task = mine.find((t) => t.title === 'تنظيف المطبخ');
    expect(task).toBeTruthy();
    expect((await m(1).client.post('/swaps', { taskId: task.id, toUserId: m(2).id })).status).toBe(403);
    const req = await m(0).client.post('/swaps', { taskId: task.id, toUserId: m(1).id, note: 'عندي اختبار' });
    expect(req.status).toBe(201);
    expect((await m(0).client.post('/swaps', { taskId: task.id, toUserId: m(2).id })).status).toBe(409);
    expect((await notificationsOf(m(1).client))[0].type).toBe('swap_request');
    expect((await m(0).client.post(`/swaps/${req.body.swap.id}/accept`)).status).toBe(403);
    const ok = await m(1).client.post(`/swaps/${req.body.swap.id}/accept`);
    expect(ok.body.swap.status).toBe('accepted');
    expect((await m(1).client.get(`/tasks/${task.id}`)).body.task.assigneeId).toBe(m(1).id);
    expect((await m(1).client.post(`/swaps/${req.body.swap.id}/reject`)).status).toBe(409);
    expect((await notificationsOf(m(0).client))[0].type).toBe('swap_response');
  });
});

describe('shared fund, expenses, debts', () => {
  it('contribution periods, payments and status', async () => {
    const r = await camp.manager.post('/contribution-periods', { title: 'نوفمبر', amountPerMember: 30000, dueDate: addDays(today, -1) });
    expect(r.status).toBe(201);
    const period = r.body.periods[0];
    expect(period.contributions).toHaveLength(8);
    expect(period.contributions.every((c) => c.status === 'overdue')).toBe(true);
    const c0 = period.contributions.find((c) => c.userId === m(0).id);
    expect((await m(0).client.post(`/contributions/${c0.id}/payments`, { amount: 30000 })).status).toBe(403);
    const paid = await camp.manager.post(`/contributions/${c0.id}/payments`, { amount: 30000 });
    expect(paid.body.periods[0].contributions.find((c) => c.userId === m(0).id).status).toBe('paid');
    expect(paid.body.fund.balance).toBe(30000);
  });

  it('member-paid shared expense creates balances that settle to zero', async () => {
    const e = await m(1).client.post('/shared-expenses', { title: 'مشتريات المطبخ', category: 'groceries', amount: 24000 });
    expect(e.status).toBe(201);
    expect(e.body.expense.payerId).toBe(m(1).id);
    expect((await m(1).client.post('/shared-expenses', { title: 'من الصندوق', amount: 1000, paidFromFund: true })).status).toBe(403);
    expect((await m(1).client.post('/shared-expenses', { title: 'باسم غيري', amount: 1000, payerId: m(2).id })).status).toBe(403);
    expect((await m(2).client.patch(`/shared-expenses/${e.body.expense.id}`, { amount: 1 })).status).toBe(403);
    const fund = await m(1).client.get('/fund');
    const nets = fund.body.members.map((x) => x.net);
    expect(nets.reduce((a, b) => a + b, 0)).toBe(0);
    expect(fund.body.me.net).toBe(21000);
    expect(fund.body.plan.reduce((s, t) => s + t.amount, 0)).toBe(21000);
    const rent = await camp.manager.post('/shared-expenses', { title: 'إيجار', category: 'rent', amount: 16000, paidFromFund: true });
    expect(rent.status).toBe(201);
    expect((await camp.manager.get('/fund')).body.fund.balance).toBe(14000);
    const s = await m(2).client.post('/settlements', { toUserId: m(1).id, amount: 3000 });
    expect(s.status).toBe(201);
    expect(s.body.members.find((x) => x.id === m(2).id).net).toBe(0);
  });

  it('debts between members with partial payments', async () => {
    const d = await m(3).client.post('/debts', { otherUserId: m(4).id, direction: 'owed', amount: 5000, title: 'سلفة' });
    expect(d.status).toBe(201);
    const id = d.body.debt.id;
    expect((await m(5).client.get(`/debts/${id}/payments`)).status).toBe(404);
    expect((await m(4).client.post(`/debts/${id}/payments`, { amount: 6000 })).status).toBe(422);
    await m(4).client.post(`/debts/${id}/payments`, { amount: 2000 });
    const last = await m(4).client.post(`/debts/${id}/payments`, { amount: 3000 });
    expect(last.body.debt.remaining).toBe(0);
    expect(last.body.debt.settledAt).toBeTruthy();
    expect((await m(4).client.post(`/debts/${id}/payments`, { amount: 1 })).status).toBe(409);
  });
});

describe('personal data is private', () => {
  it('prayers, goals, habits and budget belong to their owner', async () => {
    const a = m(0).client;
    expect((await a.put('/me/prayers', { date: today, prayer: 'fajr', done: true })).body.done).toEqual(['fajr']);
    expect((await a.put('/me/prayers', { date: addDays(today, 1), prayer: 'fajr', done: true })).status).toBe(422);
    const g = await a.post('/me/goals', { title: 'حفظ جزء عمّ', category: 'religious', steps: ['النبأ', 'النازعات'] });
    expect(g.body.goal.progress).toBe(0);
    const step = g.body.goal.steps[0];
    expect((await a.patch(`/me/goal-steps/${step.id}`, { done: true })).body.goal.progress).toBe(50);
    expect((await camp.manager.patch(`/me/goal-steps/${step.id}`, { done: false })).status).toBe(404);
    expect((await camp.manager.get('/me/goals')).body.goals).toHaveLength(0);
    const h = await a.post('/me/habits', { title: 'القراءة', days: 'daily' });
    const t = await a.post(`/me/habits/${h.body.habit.id}/toggle`, { done: true });
    expect(t.body.habit).toMatchObject({ doneToday: true, streak: 1 });
    expect((await camp.manager.post(`/me/habits/${h.body.habit.id}/toggle`, { done: true })).status).toBe(404);
  });

  it('weekly budget: 70,000 − 21,000 ⇒ 7,000 a day', async () => {
    const a = m(0).client;
    const r = await a.post('/budget/weeks', { income: 70000, essentials: [{ title: 'مواصلات', amount: 21000 }] });
    expect(r.status).toBe(201);
    expect(r.body.summary).toMatchObject({ remaining: 49000, allowedToday: 7000, daysLeft: 7 });
    const e = await a.post('/budget/expenses', { amount: 3500, category: 'food' });
    expect(e.body.summary.leftToday).toBe(3500);
    expect((await a.get('/budget/preview?income=7000')).body.allowedToday).toBe(8000);
    expect((await a.post('/budget/expenses', { amount: 100, date: addDays(today, 1) })).status).toBe(422);
    expect((await a.post('/budget/weeks', { income: 1 })).status).toBe(409); // same day
    expect((await m(1).client.get('/budget')).body.week).toBeNull();
    expect(r.body.fundShareDue).toBe(0); // m(0) paid the contribution
    expect((await m(1).client.get('/budget')).body.fundShareDue).toBe(30000);
  });

  it('home dashboard', async () => {
    const r = await m(0).client.get('/home');
    expect(r.status).toBe(200);
    expect(r.body.prayers).toEqual(['fajr']);
    expect(r.body.budget.summary.allowedToday).toBe(7000);
    expect(r.body.manager).toBeNull();
    const mgr = await camp.manager.get('/home');
    expect(mgr.body.manager).toBeTruthy();
    expect(mgr.body.contributionsDue[0]).toMatchObject({ remaining: 30000, overdue: true });
  });

  it('settings and notification preferences', async () => {
    const r = await m(0).client.patch('/me', { settings: { theme: 'dark', notifications: { disabled: ['morning_summary'], quietFrom: '23:00', quietTo: '06:00' } } });
    expect(r.body.user.settings).toMatchObject({ theme: 'dark', notifications: { disabled: ['morning_summary'], quietFrom: '23:00' } });
    const exp = await m(0).client.get('/me/export');
    expect(exp.body.prayers).toHaveLength(1);
  });
});

describe('scheduled jobs', () => {
  it('reminds two hours before and once when overdue', async () => {
    const due = addDays(today, 1);
    const t = await camp.manager.post('/tasks', { kind: 'company', title: 'اجتماع العميل', assigneeIds: [m(5).id], dueDate: due, dueTime: '10:00' });
    const id = t.body.tasks[0].id;
    const before = adenToInstant(due, '08:30');
    await runScheduled(env, before);
    let notes = await notificationsOf(m(5).client);
    expect(notes.filter((n) => n.type === 'task_reminder' && n.link === `/task/${id}`)).toHaveLength(1);
    await runScheduled(env, before);
    notes = await notificationsOf(m(5).client);
    expect(notes.filter((n) => n.type === 'task_reminder' && n.link === `/task/${id}`)).toHaveLength(1);
    const after = adenToInstant(due, '10:20');
    await runScheduled(env, after);
    await runScheduled(env, after);
    notes = await notificationsOf(m(5).client);
    expect(notes.filter((n) => n.type === 'task_overdue' && n.link === `/task/${id}`)).toHaveLength(1);
  });

  it('builds next week’s draft on Thursday evening, once', async () => {
    let thursday = today;
    while (new Date(`${thursday}T00:00:00Z`).getUTCDay() !== 4) thursday = addDays(thursday, 1);
    const at = adenToInstant(thursday, '18:30');
    const r = await runScheduled(env, at);
    expect(r.draft).toBe(true);
    const next = addDays(weekStartOf(thursday), 7);
    const view = await camp.manager.get(`/distributions/${next}`);
    expect(view.body.distribution.status).toBe('draft');
    expect((await runScheduled(env, at)).draft).toBe(false);
  });
});
