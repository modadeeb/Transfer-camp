<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { Check } from 'lucide-vue-next';
import { DAY_NAMES, addDays, adenDate, adenTime, dayOfWeek, formatDate, weekStartOf } from '@camp/domain';
import { get, put } from '../../lib/api.js';
import { PRAYERS } from '../../lib/prayers.js';
import { useUi } from '../../stores/ui.js';
import PrayerRow from '../PrayerRow.vue';
import WeekNav from '../WeekNav.vue';
import SectionCard from '../ui/SectionCard.vue';

const ui = useUi();
const today = adenDate();
const week = ref(weekStartOf(today));
const logs = ref([]);
const day = ref(today);

async function load() {
  try {
    logs.value = (await get('/me/prayers', { from: week.value, to: addDays(week.value, 6) })).logs;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(week, load);
const doneOn = (date) => logs.value.filter((l) => l.date === date).map((l) => l.prayer);
const dates = computed(() => Array.from({ length: 7 }, (_, i) => addDays(week.value, i)));
const total = computed(() => logs.value.length);

async function toggle(date, key) {
  if (date > today) return;
  const done = doneOn(date).includes(key);
  logs.value = done ? logs.value.filter((l) => !(l.date === date && l.prayer === key)) : [...logs.value, { date, prayer: key }];
  try {
    await put('/me/prayers', { date, prayer: key, done: !done });
    ui.bump('personal');
  } catch (e) {
    ui.error(e);
    load();
  }
}
</script>

<template>
  <div class="space-y-5">
    <SectionCard :title="day === today ? 'صلوات اليوم' : formatDate(day, { weekday: true })" subtitle="أوقات عدن · أم القرى">
      <template #action>
        <input v-model="day" type="date" class="input w-auto" :max="today" aria-label="اليوم" @change="week = weekStartOf(day)" />
      </template>
      <PrayerRow :date="day" :done="doneOn(day)" :now="adenTime()" :is-today="day === today" @toggle="toggle(day, $event)" />
    </SectionCard>

    <SectionCard title="سجل الأسبوع" :subtitle="`${total} من ${7 * 5}`">
      <template #action><WeekNav v-model="week" /></template>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[420px] text-center text-[13.5px]">
          <caption class="sr-only">سجل الصلوات خلال الأسبوع</caption>
          <thead>
            <tr><th scope="col" class="py-2 text-start font-medium text-muted">اليوم</th><th v-for="p in PRAYERS" :key="p.key" scope="col" class="py-2 font-medium text-muted">{{ p.name }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="d in dates" :key="d" class="border-t border-line" :class="d === today && 'bg-brass-soft'">
              <th scope="row" class="py-2 text-start font-medium">{{ DAY_NAMES[dayOfWeek(d)] }}</th>
              <td v-for="p in PRAYERS" :key="p.key" class="py-1.5">
                <button
                  type="button"
                  role="checkbox"
                  :aria-checked="doneOn(d).includes(p.key)"
                  :aria-label="`${p.name} ${DAY_NAMES[dayOfWeek(d)]}`"
                  :disabled="d > today"
                  class="mx-auto grid size-7 place-items-center rounded-full border-2 disabled:opacity-30"
                  :class="doneOn(d).includes(p.key) ? 'border-sage bg-sage text-white' : 'border-line text-transparent hover:border-sage'"
                  @click="toggle(d, p.key)"
                >
                  <Check class="size-3.5" stroke-width="3" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </SectionCard>
  </div>
</template>
