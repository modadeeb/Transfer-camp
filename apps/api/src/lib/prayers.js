// Prayer times for Aden (Umm al-Qura), same as the web app (apps/web/src/lib/prayers.js).
// Returned by the API so the mobile app shows identical times.
import { CalculationMethod, Coordinates, PrayerTimes } from 'adhan';
import { adenTime } from '@camp/domain';

const ADEN = new Coordinates(12.7855, 45.0187);
export const PRAYER_KEYS = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

/** { fajr: 'HH:MM', … } in Aden time for an Aden calendar date. */
export function prayerTimes(date) {
  const [y, m, d] = date.split('-').map(Number);
  // adhan uses the date's local Y/M/D; build it at noon UTC so any runtime timezone gives the same day.
  const times = new PrayerTimes(ADEN, new Date(Date.UTC(y, m - 1, d, 12)), CalculationMethod.UmmAlQura());
  return Object.fromEntries(PRAYER_KEYS.map((k) => [k, adenTime(times[k])]));
}
