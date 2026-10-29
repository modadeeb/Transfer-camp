export class HttpError extends Error {
  constructor(status, message, fields = undefined) {
    super(message);
    this.status = status;
    this.fields = fields;
  }
}

export const badRequest = (message, fields) => new HttpError(422, message, fields);
export const forbidden = (message = 'ليس لديك صلاحية لهذا الإجراء') => new HttpError(403, message);
export const notFound = (message = 'العنصر غير موجود') => new HttpError(404, message);
export const conflict = (message) => new HttpError(409, message);

export function parseId(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw notFound();
  return n;
}

export async function readJson(c) {
  try {
    const body = await c.req.json();
    return body && typeof body === 'object' ? body : {};
  } catch {
    return {};
  }
}
