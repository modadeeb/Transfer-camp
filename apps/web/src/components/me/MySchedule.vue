<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { CalendarOff, GraduationCap, Plus, Users, Wrench, X } from 'lucide-vue-next';
import { DAY_NAMES, adenDate, dayOfWeek, formatDate, formatTime, weekStartOf } from '@camp/domain';
import { del, get } from '../../lib/api.js';
import { SLOT_KINDS } from '../../lib/format.js';
import { useTaskActions } from '../../lib/useTaskActions.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import WeekNav from '../WeekNav.vue';
import TaskDialogs from '../tasks/TaskDialogs.vue';
import TaskRow from '../tasks/TaskRow.vue';
import UButton from '../ui/UButton.vue';
import SlotsEditor from '../SlotsEditor.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const week = ref(weekStartOf(adenDate()));
const data = ref(null);
const editSlots = ref(false);
const ta = useTaskActions(() => load());

async function load() {
  try {
    data.value = await get('/schedule/me', { weekStart: week.value });
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(week, load);
watch(() => [ui.versions.tasks, ui.versions.members], load);

const days = computed(() =>
  (data.value?.dates || []).map((date) => {
    const dow = dayOfWeek(date);
    const items = [
      ...data.value.slots.filter((s) => s.dow === dow).map((s) => ({ type: 'slot', time: s.startTime, s })),
      ...data.value.events.filter((e) => e.date === date).map((e) => ({ type: 'event', time: e.startTime || '00:00', e })),
      ...data.value.tasks.filter((t) => t.dueDate === date).map((t) => ({ type: 'task', time: t.dueTime || '99:99', t })),
    ].sort((a, b) => a.time.localeCompare(b.time));
    const away = data.value.absences.some((a) => a.startDate <= date && a.endDate >= date);
    return { date, items, away, today: date === data.value.today };
  }),
);
const undated = computed(() => (data.value?.tasks || []).filter((t) => !t.dueDate));

function openSlots() {
  editSlots.value = true;
}
async function removeAbsence(a) {
  if (!(await ui.confirm({ title: 'إلغاء الغياب؟', confirmLabel: 'إلغاء الغياب' }))) return;
  try {
    await del(`/absences/${a.id}`);
    ui.toast('أُلغي الغياب');
    load();
  } catch (e) {
    ui.error(e);
  }
}
const SLOT_ICON = { university: GraduationCap, work: Wrench, other: Users };
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <WeekNav v-model="week" />
      <div class="flex gap-2">
        <UButton variant="secondary" size="sm" @click="openSlots">أوقات الجامعة والعمل</UButton>
        <UButton variant="secondary" size="sm" :icon="CalendarOff" @click="ui.quickAdd = 'absence'">غياب</UButton>
        <UButton size="sm" :icon="Plus" @click="ui.quickAdd = 'task'">مهمة</UButton>
      </div>
    </div>
    <div v-if="data?.absences.length" class="flex flex-wrap gap-2">
      <span v-for="a in data.absences" :key="a.id" class="chip bg-brass-soft text-[color:var(--brass)]">
        غياب {{ formatDate(a.startDate) }} – {{ formatDate(a.endDate) }}
        <button type="button" class="grid size-5 place-items-center rounded-full hover:bg-black/5" aria-label="إلغاء الغياب" @click="removeAbsence(a)"><X class="size-3.5" /></button>
      </span>
    </div>
    <USkeleton v-if="!data" :lines="5" />
    <div v-else class="space-y-3">
      <section v-for="d in days" :key="d.date" class="section" :class="d.today && '!border-brass'">
        <h3 class="flex items-center gap-2 px-4 pt-3 font-semibold">
          <span v-if="d.today" class="size-2 rounded-full bg-brass" aria-hidden="true" />
          {{ DAY_NAMES[dayOfWeek(d.date)] }} <span class="num text-[13px] font-normal text-muted">{{ formatDate(d.date) }}</span>
          <span v-if="d.away" class="chip ms-auto bg-brass-soft text-[color:var(--brass)]">غائب</span>
        </h3>
        <ul class="px-2 pb-2 pt-1">
          <template v-for="(it, i) in d.items" :key="i">
            <li v-if="it.type === 'slot'" class="flex items-center gap-3 px-2 py-2">
              <span class="num w-28 shrink-0 text-[13px] text-muted">{{ formatTime(it.s.startTime) }} – {{ formatTime(it.s.endTime) }}</span>
              <component :is="SLOT_ICON[it.s.kind]" class="size-4 text-[color:var(--brass)]" />
              <span class="font-medium">{{ it.s.label || SLOT_KINDS[it.s.kind] }}</span>
            </li>
            <li v-else-if="it.type === 'event'" class="flex items-center gap-3 px-2 py-2">
              <span class="num w-28 shrink-0 text-[13px] text-muted">{{ it.e.startTime ? formatTime(it.e.startTime) : 'طوال اليوم' }}</span>
              <Users class="size-4 text-sage" />
              <span class="font-medium">{{ it.e.title }}</span>
            </li>
            <TaskRow v-else :task="it.t" :ta="ta" :show-date="false" />
          </template>
          <li v-if="!d.items.length" class="px-2 py-2 text-[13.5px] text-muted">يوم حر</li>
        </ul>
      </section>
      <section v-if="undated.length" class="section">
        <h3 class="px-4 pt-3 font-semibold">بلا موعد</h3>
        <ul class="px-2 pb-2"><TaskRow v-for="t in undated" :key="t.id" :task="t" :ta="ta" /></ul>
      </section>
    </div>
    <TaskDialogs :ta="ta" />

    <SlotsEditor :open="editSlots" :user-id="session.user.id" :slots="data?.slots || []" title="أوقاتي الثابتة كل أسبوع" @close="editSlots = false" @saved="load" />
  </div>
</template>
