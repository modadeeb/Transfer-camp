<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { Dumbbell, Moon, Plus, Trash2 } from 'lucide-vue-next';
import { DAY_NAMES, addDays, adenDate, dayOfWeek, formatDate, formatDuration, formatTime, sleepMinutes, weekStartOf } from '@camp/domain';
import { del, get, post, put } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import WeekNav from '../WeekNav.vue';
import SectionCard from '../ui/SectionCard.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';

const session = useSession();
const ui = useUi();
const today = adenDate();
const week = ref(weekStartOf(today));
const sleep = ref([]);
const workouts = ref([]);
const sleepForm = useForm({ date: today, sleptAt: '23:00', wokeAt: '06:00' });
const workoutOpen = ref(false);
const workout = useForm({ type: 'جري', durationMin: 30, date: today });
const TYPES = ['جري', 'مشي', 'نادي', 'كرة قدم', 'سباحة', 'تمارين منزلية'];

const goalFrom = computed(() => session.settings.sleepFrom || '23:00');
const goalTo = computed(() => session.settings.sleepTo || '06:00');
const goalMinutes = computed(() => sleepMinutes(goalFrom.value, goalTo.value));
const workoutGoal = computed(() => session.settings.workoutsPerWeek ?? 4);

async function load() {
  try {
    const q = { from: week.value, to: addDays(week.value, 6) };
    const [s, w] = await Promise.all([get('/me/sleep', q), get('/me/workouts', q)]);
    sleep.value = s.logs;
    workouts.value = w.workouts;
    const t = s.logs.find((l) => l.date === sleepForm.form.date);
    if (t) Object.assign(sleepForm.form, { sleptAt: t.sleptAt, wokeAt: t.wokeAt });
  } catch (e) {
    ui.error(e);
  }
}
onMounted(() => {
  Object.assign(sleepForm.form, { sleptAt: goalFrom.value, wokeAt: goalTo.value });
  load();
});
watch(week, load);

const dates = computed(() => Array.from({ length: 7 }, (_, i) => addDays(week.value, i)));
const sleepOn = (d) => sleep.value.find((l) => l.date === d);
const workoutDays = computed(() => new Set(workouts.value.map((w) => w.date)));

async function saveSleep() {
  const r = await sleepForm.submit(() => put('/me/sleep', { ...sleepForm.form }));
  if (!r) return;
  ui.toast(`سُجّل نومك: ${formatDuration(r.log.minutes)}`);
  ui.bump('personal');
  load();
}
async function saveWorkout() {
  const r = await workout.submit(() => post('/me/workouts', { type: workout.form.type, durationMin: workout.form.durationMin || null, date: workout.form.date }));
  if (!r) return;
  workoutOpen.value = false;
  const count = new Set([...workoutDays.value, r.workout.date]).size;
  ui.toast(count >= workoutGoal.value ? `أحسنت! حققت هدف الأسبوع (${count} من ${workoutGoal.value})` : `سُجّل التمرين · ${count} من ${workoutGoal.value} هذا الأسبوع`);
  ui.bump('personal');
  load();
}
async function removeWorkout(w) {
  if (!(await ui.confirm({ title: 'حذف التمرين؟', confirmLabel: 'حذف', danger: true }))) return;
  try {
    await del(`/me/workouts/${w.id}`);
    ui.toast('حُذف التمرين');
    load();
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-5">
    <div class="flex justify-end"><WeekNav v-model="week" /></div>
    <div class="grid gap-5 lg:grid-cols-2">
      <SectionCard title="النوم" :subtitle="`الهدف ${formatTime(goalFrom)} ← ${formatTime(goalTo)} (${formatDuration(goalMinutes)})`">
        <form class="grid grid-cols-2 items-end gap-2 sm:grid-cols-[1fr_1fr_1fr_auto]" @submit.prevent="saveSleep">
          <UField v-slot="{ id }" label="الليلة"><input :id="id" v-model="sleepForm.form.date" type="date" class="input" :max="today" /></UField>
          <UField v-slot="{ id }" label="نمت"><input :id="id" v-model="sleepForm.form.sleptAt" type="time" class="input" /></UField>
          <UField v-slot="{ id }" label="استيقظت"><input :id="id" v-model="sleepForm.form.wokeAt" type="time" class="input" /></UField>
          <UButton type="submit" :loading="sleepForm.saving.value" :icon="Moon">حفظ</UButton>
        </form>
        <ul class="mt-4 space-y-1.5" aria-label="نوم الأسبوع">
          <li v-for="d in dates" :key="d" class="flex items-center gap-3">
            <span class="w-16 shrink-0 text-[13.5px]" :class="d === today && 'font-semibold'">{{ DAY_NAMES[dayOfWeek(d)] }}</span>
            <span class="relative h-2.5 flex-1 overflow-hidden rounded-full bg-sunken">
              <span v-if="sleepOn(d)" class="absolute inset-y-0 start-0 rounded-full" :class="sleepOn(d).minutes >= goalMinutes - 30 ? 'bg-sage' : 'bg-brass'" :style="{ width: `${Math.min(100, (sleepOn(d).minutes / 600) * 100)}%` }" />
              <span class="absolute inset-y-0 w-px bg-ink/30" :style="{ insetInlineStart: `${(goalMinutes / 600) * 100}%` }" aria-hidden="true" />
            </span>
            <span class="num w-16 shrink-0 text-end text-[13px]">{{ sleepOn(d) ? formatDuration(sleepOn(d).minutes) : '—' }}</span>
          </li>
        </ul>
      </SectionCard>

      <SectionCard title="الرياضة" :subtitle="`${workoutDays.size} من ${workoutGoal} أيام هذا الأسبوع`">
        <template #action><UButton size="sm" :icon="Plus" @click="(workout.reset({ type: 'جري', durationMin: 30, date: today })), (workoutOpen = true)">تمرّنت</UButton></template>
        <ul class="flex justify-between gap-1" aria-label="أيام التمرين">
          <li v-for="d in dates" :key="d" class="flex flex-col items-center gap-1">
            <span class="grid size-9 place-items-center rounded-full border-2" :class="workoutDays.has(d) ? 'border-sage bg-sage text-white' : d === today ? 'border-brass' : 'border-line'">
              <Dumbbell v-if="workoutDays.has(d)" class="size-4" />
            </span>
            <span class="text-[12px] text-muted">{{ DAY_NAMES[dayOfWeek(d)].replace('ال', '') }}</span>
          </li>
        </ul>
        <ul v-if="workouts.length" class="mt-4 divide-y divide-line">
          <li v-for="w in workouts" :key="w.id" class="flex items-center gap-3 py-2">
            <span class="flex-1">{{ w.type }}<span v-if="w.durationMin" class="num text-muted"> · {{ w.durationMin }} د</span></span>
            <span class="text-[13px] text-muted">{{ formatDate(w.date, { weekday: true }) }}</span>
            <button type="button" class="grid size-8 place-items-center rounded-full text-muted hover:text-danger" :aria-label="`حذف ${w.type}`" @click="removeWorkout(w)"><Trash2 class="size-4" /></button>
          </li>
        </ul>
      </SectionCard>
    </div>

    <UDialog :open="workoutOpen" title="تسجيل تمرين" @close="workoutOpen = false">
      <form id="workout-form" class="space-y-4" @submit.prevent="saveWorkout">
        <UField label="النوع" :error="workout.errors.value.type">
          <USegment v-model="workout.form.type" :options="TYPES.map((t) => ({ value: t, label: t }))" label="نوع التمرين" />
        </UField>
        <div class="grid grid-cols-2 gap-4">
          <UField v-slot="{ id }" label="المدة بالدقائق" optional :error="workout.errors.value.durationMin"><input :id="id" v-model.number="workout.form.durationMin" type="number" min="1" max="600" class="input num" /></UField>
          <UField v-slot="{ id }" label="اليوم" :error="workout.errors.value.date"><input :id="id" v-model="workout.form.date" type="date" class="input" :max="today" /></UField>
        </div>
      </form>
      <template #footer>
        <UButton type="submit" form="workout-form" :loading="workout.saving.value" class="flex-1">تسجيل</UButton>
        <UButton variant="secondary" @click="workoutOpen = false">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
