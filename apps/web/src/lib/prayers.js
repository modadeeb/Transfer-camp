// Prayer times for Aden, computed locally (no network needed).
import { CalculationMethod, Coordinates, PrayerTimes } from 'adhan';
import { adenTime } from '@camp/domain';

const ADEN = new Coordinates(12.7855, 45.0187);

export const PRAYERS = [
  { key: 'fajr', name: 'الفجر' },
  { key: 'dhuhr', name: 'الظهر' },
  { key: 'asr', name: 'العصر' },
  { key: 'maghrib', name: 'المغرب' },
  { key: 'isha', name: 'العشاء' },
];

/** Times ('HH:MM', Aden) for an Aden calendar date. */
export function prayerTimes(date) {
  const [y, m, d] = date.split('-').map(Number);
  const times = new PrayerTimes(ADEN, new Date(y, m - 1, d), CalculationMethod.UmmAlQura());
  return Object.fromEntries(PRAYERS.map((p) => [p.key, adenTime(times[p.key])]));
}

/** The next prayer for today (or null after Isha). */
export function nextPrayer(date, now) {
  const times = prayerTimes(date);
  return PRAYERS.find((p) => times[p.key] > now) || null;
}
