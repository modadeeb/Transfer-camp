// Tiny validator with Arabic messages. A schema is an object of field rules.
// parse(body, schema)                -> all required fields must be present
// parse(body, schema, {partial:true}) -> only validates keys present in body (PATCH)
import { isDate, isTime } from '@camp/domain';
import { badRequest } from './http.js';

const REQUIRED = 'هذا الحقل مطلوب';

function rule(check, { optional = false, nullable = false, defaultValue } = {}) {
  return { check, optional, nullable, defaultValue };
}

export const v = {
  string: ({ min = 1, max = 500, ...o } = {}) =>
    rule((x) => {
      if (typeof x !== 'string') throw new Error('قيمة غير صالحة');
      const s = x.trim();
      if (s.length < min) throw new Error(min > 1 ? `الحد الأدنى ${min} أحرف` : REQUIRED);
      if (s.length > max) throw new Error(`الحد الأقصى ${max} حرف`);
      return s;
    }, o),
  text: ({ max = 5000, ...o } = {}) =>
    rule((x) => {
      if (typeof x !== 'string') throw new Error('قيمة غير صالحة');
      const s = x.trim();
      if (s.length > max) throw new Error(`الحد الأقصى ${max} حرف`);
      return s || null;
    }, { optional: true, nullable: true, ...o }),
  int: ({ min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER, ...o } = {}) =>
    rule((x) => {
      const n = typeof x === 'string' && x.trim() !== '' ? Number(x) : x;
      if (typeof n !== 'number' || !Number.isInteger(n)) throw new Error('أدخل رقماً صحيحاً');
      if (n < min) throw new Error(`أقل قيمة ${min}`);
      if (n > max) throw new Error(`أكبر قيمة ${max}`);
      return n;
    }, o),
  money: ({ min = 1, ...o } = {}) => v.int({ min, max: 1_000_000_000, ...o }),
  id: (o = {}) => v.int({ min: 1, ...o }),
  bool: (o = {}) =>
    rule((x) => {
      if (typeof x !== 'boolean') throw new Error('قيمة غير صالحة');
      return x;
    }, o),
  enum: (values, o = {}) =>
    rule((x) => {
      if (!values.includes(x)) throw new Error('اختيار غير صالح');
      return x;
    }, o),
  date: (o = {}) =>
    rule((x) => {
      if (!isDate(x)) throw new Error('تاريخ غير صالح');
      return x;
    }, o),
  time: (o = {}) =>
    rule((x) => {
      if (!isTime(x)) throw new Error('وقت غير صالح');
      return x;
    }, o),
  url: (o = {}) =>
    rule((x) => {
      if (typeof x !== 'string') throw new Error('رابط غير صالح');
      const s = x.trim();
      let u;
      try {
        u = new URL(s);
      } catch {
        throw new Error('رابط غير صالح');
      }
      if (!['http:', 'https:'].includes(u.protocol)) throw new Error('رابط غير صالح');
      if (s.length > 1000) throw new Error('الرابط طويل جداً');
      return s;
    }, o),
  array: (item, { min = 0, max = 100, ...o } = {}) =>
    rule((x) => {
      if (!Array.isArray(x)) throw new Error('قيمة غير صالحة');
      if (x.length < min) throw new Error(min === 1 ? 'اختر عنصراً واحداً على الأقل' : `اختر ${min} على الأقل`);
      if (x.length > max) throw new Error(`الحد الأقصى ${max}`);
      return x.map((el) => {
        if (el === undefined || el === null) throw new Error('قيمة غير صالحة');
        return item.check(el);
      });
    }, o),
  object: (shape, o = {}) =>
    rule((x) => {
      if (!x || typeof x !== 'object' || Array.isArray(x)) throw new Error('قيمة غير صالحة');
      return parseShape(x, shape, false, true);
    }, o),
};

function parseShape(body, schema, partial, nested) {
  const out = {};
  const fields = {};
  for (const [key, r] of Object.entries(schema)) {
    const present = Object.prototype.hasOwnProperty.call(body, key) && body[key] !== undefined;
    if (!present) {
      if (partial) continue;
      if (r.defaultValue !== undefined) out[key] = r.defaultValue;
      else if (r.optional) out[key] = null;
      else fields[key] = REQUIRED;
      continue;
    }
    const value = body[key];
    if (value === null || value === '') {
      if (r.nullable || r.optional) {
        out[key] = null;
        continue;
      }
      fields[key] = REQUIRED;
      continue;
    }
    try {
      out[key] = r.check(value);
    } catch (e) {
      fields[key] = e.message;
    }
  }
  if (Object.keys(fields).length) {
    if (nested) throw new Error(Object.values(fields)[0]);
    throw badRequest(Object.values(fields)[0], fields);
  }
  return out;
}

export function parse(body, schema, { partial = false } = {}) {
  return parseShape(body || {}, schema, partial, false);
}
