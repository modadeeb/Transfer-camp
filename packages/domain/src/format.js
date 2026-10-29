// Display helpers shared by web and API (notification texts).
const AR_MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const AR_DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/** 12,500 ر.ي — whole rials, Latin digits with thousands separators. */
export function formatMoney(amount, { unit = true } = {}) {
  const n = Math.round(Number(amount) || 0);
  const s = Math.abs(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${n < 0 ? '−' : ''}${s}${unit ? ' ر.ي' : ''}`;
}

export function formatDate(date, { weekday = false, year = false } = {}) {
  if (!date) return '';
  const [y, m, d] = date.split('-').map(Number);
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return `${weekday ? `${AR_DAYS[dow]} ` : ''}${d} ${AR_MONTHS[m - 1]}${year ? ` ${y}` : ''}`;
}

export function formatMonth(date) {
  const [y, m] = date.split('-').map(Number);
  return `${AR_MONTHS[m - 1]} ${y}`;
}

/** 14:30 -> 2:30 م */
export function formatTime(time) {
  if (!time) return '';
  const [h, m] = time.split(':').map(Number);
  const suffix = h < 12 ? 'ص' : 'م';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, '0')} ${suffix}`;
}

export function formatDuration(minutes) {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (!h) return `${m} د`;
  return m ? `${h} س ${m} د` : `${h} س`;
}
