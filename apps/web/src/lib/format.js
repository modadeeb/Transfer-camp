export {
  formatMoney,
  formatDate,
  formatMonth,
  formatTime,
  formatDuration,
  DAY_NAMES,
  WEEK_ORDER,
  STATUS_LABELS,
  PRIORITY_LABELS,
  KIND_LABELS,
  SPECIALTIES,
  SLOT_LABELS,
  adenDate,
  adenTime,
  addDays,
  weekStartOf,
  weekDates,
  dayOfWeek,
  diffDays,
  sleepMinutes,
} from '@camp/domain';

import { adenDate, addDays, formatDate } from '@camp/domain';

/** «اليوم»، «غداً»، «أمس» or the formatted date. */
export function relativeDay(date) {
  if (!date) return 'بلا موعد';
  const today = adenDate();
  if (date === today) return 'اليوم';
  if (date === addDays(today, 1)) return 'غداً';
  if (date === addDays(today, -1)) return 'أمس';
  return formatDate(date, { weekday: true });
}

export function timeAgo(iso) {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'الآن';
  if (diff < 3600) return `قبل ${Math.floor(diff / 60)} د`;
  if (diff < 86400) return `قبل ${Math.floor(diff / 3600)} س`;
  const days = Math.floor(diff / 86400);
  return days === 1 ? 'أمس' : `قبل ${days} أيام`;
}

export function greeting(time) {
  const h = Number(time.slice(0, 2));
  if (h < 12) return 'صباح الخير';
  if (h < 18) return 'مساء الخير';
  return 'مساء النور';
}

export const GOAL_CATEGORIES = {
  religious: 'ديني',
  study: 'دراسي',
  health: 'صحي',
  money: 'مالي',
  work: 'مهني',
  personal: 'شخصي',
};

export const SLOT_KINDS = { university: 'جامعة', work: 'عمل', other: 'أخرى' };

export const EXPENSE_CATEGORIES = {
  rent: 'إيجار',
  electricity: 'كهرباء',
  water: 'ماء',
  internet: 'إنترنت',
  groceries: 'مشتريات المطبخ',
  cleaning: 'منظفات',
  gas: 'غاز',
  maintenance: 'صيانة',
  other: 'أخرى',
};

export const PERSONAL_CATEGORIES = { food: 'طعام', transport: 'مواصلات', study: 'دراسة', phone: 'اتصالات', personal: 'شخصي', other: 'أخرى' };
export const INCOME_SOURCES = { salary: 'راتب', freelance: 'عمل حر', family: 'من الأهل', gift: 'هدية', other: 'أخرى' };

export { count, TASKS, ITEMS, POINTS, HOURS } from '@camp/domain';
