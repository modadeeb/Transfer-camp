import { adenTime, timeToMinutes } from '@camp/domain';
import { all, inList, nowIso, run } from './db.js';
import { fcmConfigured, sendPush } from './fcm.js';

export const NOTIFICATION_TYPES = {
  task_assigned: 'مهمة جديدة',
  task_updated: 'تعديل مهمة',
  task_deleted: 'حذف مهمة',
  task_reminder: 'تذكير بموعد',
  task_overdue: 'تجاوز الموعد',
  task_returned: 'إعادة مهمة',
  task_submitted: 'مهمة بانتظار الاعتماد',
  task_approved: 'اعتماد مهمة',
  swap_request: 'طلب تبديل',
  swap_response: 'رد على طلب تبديل',
  contribution_due: 'مساهمة الصندوق',
  debt_payment: 'تسديد دين',
  morning_summary: 'الملخص الصباحي',
  overdue_summary: 'ملخص المتأخرات',
  distribution: 'توزيع الأسبوع',
};

function prefs(user) {
  try {
    return JSON.parse(user.settings || '{}').notifications || {};
  } catch {
    return {};
  }
}

export function inQuietHours(p, now = new Date()) {
  if (!p.quietFrom || !p.quietTo) return false;
  const t = timeToMinutes(adenTime(now));
  const from = timeToMinutes(p.quietFrom);
  const to = timeToMinutes(p.quietTo);
  return from <= to ? t >= from && t < to : t >= from || t < to;
}

/**
 * Store in-app notifications and (if Firebase is configured) send pushes.
 * @param {{env:object, waitUntil?:Function}} ctx
 * @param {number[]} userIds
 * @param {{type:string,title:string,body?:string,link?:string,urgent?:boolean}} n
 */
export async function notify(ctx, userIds, n) {
  const ids = [...new Set(userIds.filter((id) => id != null))];
  if (!ids.length) return;
  const { env } = ctx;
  const users = await all(
    env.DB,
    `SELECT id, settings FROM users WHERE id IN (${inList(ids)}) AND deleted_at IS NULL AND archived_at IS NULL`,
    ...ids,
  );
  const created = nowIso();
  const pushTo = [];
  for (const u of users) {
    const p = prefs(u);
    if (Array.isArray(p.disabled) && p.disabled.includes(n.type) && !n.urgent) continue;
    await run(
      env.DB,
      'INSERT INTO notifications (user_id, type, title, body, link, urgent, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      u.id,
      n.type,
      n.title,
      n.body || null,
      n.link || null,
      n.urgent ? 1 : 0,
      created,
    );
    if (!inQuietHours(p) || n.urgent) pushTo.push(u.id);
  }
  if (!pushTo.length || !fcmConfigured(env)) return;

  const job = (async () => {
    const tokens = await all(env.DB, `SELECT token FROM device_tokens WHERE user_id IN (${inList(pushTo)})`, ...pushTo);
    for (const { token } of tokens) {
      try {
        const result = await sendPush(env, token, { title: n.title, body: n.body, link: n.link, tag: n.type });
        if (result === 'invalid') await run(env.DB, 'DELETE FROM device_tokens WHERE token = ?', token);
      } catch (e) {
        console.error('push failed', e?.message);
      }
    }
  })();
  if (ctx.waitUntil) ctx.waitUntil(job);
  else await job;
}

/** Build the notify context from a Hono request context. */
export function fromRequest(c) {
  let waitUntil;
  try {
    const ec = c.executionCtx;
    waitUntil = (p) => ec.waitUntil(p);
  } catch {
    waitUntil = undefined;
  }
  return { env: c.env, waitUntil };
}
