import { Hono } from 'hono';
import { secureHeaders } from 'hono/secure-headers';
import { csrf, requireAuth } from './lib/auth.js';
import { HttpError } from './lib/http.js';
import { runScheduled } from './cron.js';
import auth from './routes/auth.js';
import budget from './routes/budget.js';
import common from './routes/common.js';
import housing from './routes/housing.js';
import members from './routes/members.js';
import money from './routes/money.js';
import overview from './routes/overview.js';
import personal from './routes/personal.js';
import tasks from './routes/tasks.js';
import work from './routes/work.js';

export const app = new Hono().basePath('/api');

app.use('*', secureHeaders());
app.use('*', async (c, next) => {
  await next();
  c.header('Cache-Control', 'no-store');
});
app.use('*', csrf);

app.get('/health', (c) => c.json({ ok: true }));

// Public: first-run setup, login, logout.
app.route('/', auth);

// Everything else requires a session.
const secured = new Hono();
secured.use('*', requireAuth);
for (const r of [members, housing, tasks, work, money, personal, budget, overview, common]) secured.route('/', r);
app.route('/', secured);

app.notFound((c) => c.json({ error: 'المسار غير موجود' }, 404));

app.onError((err, c) => {
  if (err instanceof HttpError) {
    return c.json({ error: err.message, ...(err.fields ? { fields: err.fields } : {}) }, err.status);
  }
  if (String(err?.message || '').includes('UNIQUE constraint failed')) {
    return c.json({ error: 'العنصر موجود مسبقاً' }, 409);
  }
  console.error('Unhandled error', err?.stack || err);
  return c.json({ error: 'حدث خطأ غير متوقع. حاول مرة أخرى' }, 500);
});

export default {
  fetch: app.fetch,
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runScheduled(env, new Date(event.scheduledTime), (p) => ctx.waitUntil(p)));
  },
};
