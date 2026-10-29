export const nowIso = () => new Date().toISOString();

const clean = (params) => params.map((p) => (p === undefined ? null : typeof p === 'boolean' ? (p ? 1 : 0) : p));

export async function all(db, sql, ...params) {
  const r = await db.prepare(sql).bind(...clean(params)).all();
  return r.results || [];
}

export async function first(db, sql, ...params) {
  return (await db.prepare(sql).bind(...clean(params)).first()) ?? null;
}

export async function run(db, sql, ...params) {
  return db.prepare(sql).bind(...clean(params)).run();
}

/** Run several statements atomically (D1 batch = one transaction). */
export async function batch(db, statements) {
  if (!statements.length) return [];
  return db.batch(statements.map(([sql, ...params]) => db.prepare(sql).bind(...clean(params))));
}

export async function insert(db, table, data) {
  const keys = Object.keys(data);
  const sql = `INSERT INTO ${table} (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`;
  const r = await run(db, sql, ...keys.map((k) => data[k]));
  return r.meta.last_row_id;
}

export async function update(db, table, id, data) {
  const keys = Object.keys(data);
  if (!keys.length) return;
  const sql = `UPDATE ${table} SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`;
  await run(db, sql, ...keys.map((k) => data[k]), id);
}

export const inList = (ids) => ids.map(() => '?').join(', ') || 'NULL';

const BOOL_KEYS = new Set([
  'needs_approval',
  'active',
  'everyone',
  'paid_from_fund',
  'must_change_password',
  'urgent',
]);
const JSON_KEYS = new Set(['days', 'checklist', 'attachments', 'member_ids', 'split_member_ids', 'settings', 'summary', 'details_json']);

const camelKey = (k) => k.replace(/_([a-z])/g, (_, ch) => ch.toUpperCase());

export function camel(row, { omit = [] } = {}) {
  if (!row) return row;
  const out = {};
  for (const [k, value] of Object.entries(row)) {
    if (omit.includes(k)) continue;
    let val = value;
    if (BOOL_KEYS.has(k)) val = Boolean(value);
    else if (JSON_KEYS.has(k) && typeof value === 'string') {
      try {
        val = JSON.parse(value);
      } catch {
        val = null;
      }
    }
    out[camelKey(k)] = val;
  }
  return out;
}

export const camelAll = (rows, opts) => rows.map((r) => camel(r, opts));

export async function getSetting(db, key, fallback = null) {
  const row = await first(db, 'SELECT value FROM app_settings WHERE key = ?', key);
  return row ? row.value : fallback;
}

export async function setSetting(db, key, value) {
  await run(
    db,
    'INSERT INTO app_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    key,
    String(value),
  );
}

export async function logActivity(db, entity, entityId, actorId, action, details = null) {
  await run(
    db,
    'INSERT INTO activity_log (entity, entity_id, actor_id, action, details, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    entity,
    entityId,
    actorId,
    action,
    details ? JSON.stringify(details) : null,
    nowIso(),
  );
}
