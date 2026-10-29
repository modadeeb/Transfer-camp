// Habit streaks: consecutive due days that were done. Days a habit isn't due never break it.
// Today not done yet doesn't break the streak either (the day isn't over).
import { addDays, dayOfWeek, weekDates } from './dates.js';

export function isDue(habit, date) {
  if (!habit.days || habit.days === 'daily' || (Array.isArray(habit.days) && habit.days.length === 0)) return true;
  return habit.days.includes(dayOfWeek(date));
}

export function currentStreak(habit, doneDates, today, maxLookback = 400) {
  const done = new Set(doneDates);
  let streak = 0;
  let date = today;
  if (isDue(habit, today) && !done.has(today)) date = addDays(today, -1);
  for (let i = 0; i < maxLookback; i += 1) {
    if (isDue(habit, date)) {
      if (!done.has(date)) break;
      streak += 1;
    }
    date = addDays(date, -1);
  }
  return streak;
}

export function weekDots(habit, doneDates, weekStart) {
  const done = new Set(doneDates);
  return weekDates(weekStart).map((date) => ({ date, due: isDue(habit, date), done: done.has(date) }));
}

export function sleepMinutes(sleptAt, wokeAt) {
  const [sh, sm] = sleptAt.split(':').map(Number);
  const [wh, wm] = wokeAt.split(':').map(Number);
  let m = wh * 60 + wm - (sh * 60 + sm);
  if (m <= 0) m += 1440;
  return m;
}
