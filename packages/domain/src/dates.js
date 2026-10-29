// Date helpers. All "local" dates are Aden time (UTC+3, no DST), as 'YYYY-MM-DD' strings.
export const ADEN_OFFSET_MINUTES = 180;
export const WEEK_START_DOW = 6; // Saturday (0 = Sunday ... 6 = Saturday)

const pad = (n) => String(n).padStart(2, '0');

function toParts(date) {
  const [y, m, d] = date.split('-').map(Number);
  return { y, m, d };
}

export function isDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const { y, m, d } = toParts(value);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

export function isTime(value) {
  return typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

export function fromUtcDate(t) {
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

/** Aden calendar date for an instant. */
export function adenDate(now = new Date()) {
  return fromUtcDate(new Date(now.getTime() + ADEN_OFFSET_MINUTES * 60000));
}

/** Aden wall-clock time 'HH:MM' for an instant. */
export function adenTime(now = new Date()) {
  const t = new Date(now.getTime() + ADEN_OFFSET_MINUTES * 60000);
  return `${pad(t.getUTCHours())}:${pad(t.getUTCMinutes())}`;
}

export function addDays(date, n) {
  const { y, m, d } = toParts(date);
  return fromUtcDate(new Date(Date.UTC(y, m - 1, d + n)));
}

/** Whole days from a to b (b - a). */
export function diffDays(a, b) {
  const pa = toParts(a);
  const pb = toParts(b);
  return Math.round((Date.UTC(pb.y, pb.m - 1, pb.d) - Date.UTC(pa.y, pa.m - 1, pa.d)) / 86400000);
}

/** Day of week, 0 = Sunday ... 6 = Saturday. */
export function dayOfWeek(date) {
  const { y, m, d } = toParts(date);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

export function weekStartOf(date, startDow = WEEK_START_DOW) {
  const back = (dayOfWeek(date) - startDow + 7) % 7;
  return addDays(date, -back);
}

export function weekDates(start) {
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}

export function timeToMinutes(time) {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

export function minutesToTime(minutes) {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
}

/** Instant (Date) for an Aden local date + time. */
export function adenToInstant(date, time = '00:00') {
  const { y, m, d } = toParts(date);
  const mins = timeToMinutes(time);
  return new Date(Date.UTC(y, m - 1, d, 0, mins) - ADEN_OFFSET_MINUTES * 60000);
}

export function inRange(date, from, to) {
  return date >= from && date <= to;
}

export function monthKey(date) {
  return date.slice(0, 7);
}

export const DAY_NAMES = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
/** Days in display order starting Saturday. */
export const WEEK_ORDER = [6, 0, 1, 2, 3, 4, 5];
