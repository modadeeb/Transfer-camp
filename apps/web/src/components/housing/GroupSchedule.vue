<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { CalendarDays, Check, Plane, Users } from 'lucide-vue-next';
import { DAY_NAMES, adenDate, dayOfWeek, formatDate, formatTime, weekStartOf } from '@camp/domain';
import { get } from '../../lib/api.js';
import { TASKS, count } from '../../lib/format.js';
import { choreIcon } from '../../lib/icons.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import WeekNav from '../WeekNav.vue';
import UAvatar from '../ui/UAvatar.vue';
import UEmpty from '../ui/UEmpty.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const props = defineProps({ initialWeek: { type: String, default: null } });
const session = useSession();
const ui = useUi();
const week = ref(props.initialWeek || weekStartOf(adenDate()));
const data = ref(null);
const member = ref(null);
const kind = ref('house');
const openDay = ref(adenDate());

async function load() {
  try {
    data.value = await get('/schedule/group', { weekStart: week.value });
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(week, load);
watch(() => [ui.versions.tasks, ui.versions.housing], load);

const days = computed(() =>
  (data.value?.dates || []).map((date) => {
    const tasks = data.value.tasks.filter((t) => t.dueDate === date && (kind.value === 'all' || t.kind === kind.value) && (!member.value || t.assigneeId === member.value));
    const events = data.value.events.filter((e) => e.date === date && (!member.value || e.everyone || e.memberIds.includes(member.value)));
    const away = data.value.absences.filter((a) => a.startDate <= date && a.endDate >= date && (!member.value || a.userId === member.value));
    return { date, tasks, events, away, today: date === data.value.today };
  }),
);
const memberOptions = computed(() => [{ value: null, label: 'الكل' }, ...session.activeMembers.map((m) => ({ value: m.id, label: m.name }))]);
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <WeekNav v-model="week" />
      <USegment
        v-model="kind"
        :options="[
          { value: 'house', label: 'السكن' },
          { value: 'company', label: 'الشركة' },
          { value: 'all', label: 'الكل' },
        ]"
        label="نوع المهام"
      />
    </div>
    <div class="scrollbar-none -mx-4 overflow-x-auto px-4 lg:mx-0 lg:px-0">
      <USegment v-model="member" :options="memberOptions" label="عرض حسب العضو" class="!flex-nowrap" />
    </div>

    <USkeleton v-if="!data" :lines="5" />
    <template v-else>
      <p v-if="kind === 'house' && !data.distributionStatus" class="rounded-[12px] bg-sunken px-4 py-3 text-[14px] text-muted">
        لم يُنشر توزيع مهام السكن لهذا الأسبوع بعد.
      </p>

      <!-- Laptop: the week as seven columns; today carries the brass marker -->
      <div class="hidden gap-2 lg:grid lg:grid-cols-7">
        <section v-for="d in days" :key="d.date" class="min-h-48 rounded-[14px] border bg-card" :class="d.today ? 'border-brass' : 'border-line'" :aria-label="formatDate(d.date, { weekday: true })">
          <header class="flex items-baseline justify-between border-b border-line px-3 py-2" :class="d.today && 'bg-brass-soft'">
            <span class="font-semibold">{{ DAY_NAMES[dayOfWeek(d.date)] }}</span>
            <span class="num text-[12.5px] text-muted">{{ formatDate(d.date) }}</span>
          </header>
          <ul class="space-y-1.5 p-2">
            <li v-for="e in d.events" :key="`e${e.id}`" class="rounded-[8px] bg-sage-soft px-2 py-1.5 text-[12.5px] text-forest">
              <span class="flex items-center gap-1 font-medium"><Users class="size-3.5" />{{ e.title }}</span>
              <span v-if="e.startTime" class="num">{{ formatTime(e.startTime) }}</span>
            </li>
            <li v-for="a in d.away" :key="`a${a.id}`" class="flex items-center gap-1 px-1 text-[12px] text-muted"><Plane class="size-3.5" />{{ a.userName }} غائب</li>
            <li v-for="t in d.tasks" :key="t.id">
              <RouterLink :to="`/task/${t.id}`" class="flex items-start gap-1.5 rounded-[8px] px-1.5 py-1 hover:bg-sunken" :class="t.status === 'approved' && 'opacity-60'">
                <component :is="choreIcon(t.choreIcon)" v-if="t.kind === 'house'" class="mt-0.5 size-3.5 shrink-0 text-sage" aria-hidden="true" />
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-[13px] font-medium" :class="t.status === 'approved' && 'line-through'">{{ t.title }}</span>
                  <span class="flex items-center gap-1 text-[12px] text-muted">
                    <UAvatar :name="t.assigneeName" :color="t.assigneeColor" size="sm" class="!size-4 !text-[9px]" />
                    {{ t.assigneeName || 'بلا مكلَّف' }}
                    <Check v-if="t.status === 'approved'" class="size-3 text-sage" aria-label="منجزة" />
                  </span>
                </span>
              </RouterLink>
            </li>
            <li v-if="!d.tasks.length && !d.events.length" class="px-1 py-2 text-[12.5px] text-muted">لا شيء</li>
          </ul>
        </section>
      </div>

      <!-- Phone: days as a list, today open -->
      <div class="space-y-2 lg:hidden">
        <section v-for="d in days" :key="d.date" class="section overflow-hidden" :class="d.today && '!border-brass'">
          <button type="button" class="flex w-full items-center justify-between px-4 py-3" :aria-expanded="openDay === d.date" @click="openDay = openDay === d.date ? null : d.date">
            <span class="flex items-center gap-2 font-semibold">
              <span v-if="d.today" class="size-2 rounded-full bg-brass" aria-hidden="true" />
              {{ DAY_NAMES[dayOfWeek(d.date)] }}
              <span class="num text-[13px] font-normal text-muted">{{ formatDate(d.date) }}</span>
            </span>
            <span class="num text-[13px] text-muted">{{ d.tasks.length ? count(d.tasks.length, TASKS) : 'لا شيء' }}</span>
          </button>
          <ul v-if="openDay === d.date" class="space-y-1 border-t border-line px-3 py-2">
            <li v-for="e in d.events" :key="`e${e.id}`" class="flex items-center gap-2 rounded-[8px] bg-sage-soft px-3 py-2 text-[14px] text-forest">
              <Users class="size-4" />{{ e.title }} <span v-if="e.startTime" class="num ms-auto">{{ formatTime(e.startTime) }}</span>
            </li>
            <li v-for="a in d.away" :key="`a${a.id}`" class="flex items-center gap-2 px-3 py-1 text-[13px] text-muted"><Plane class="size-4" />{{ a.userName }} غائب</li>
            <li v-for="t in d.tasks" :key="t.id">
              <RouterLink :to="`/task/${t.id}`" class="flex items-center gap-3 rounded-[8px] px-2 py-2 hover:bg-sunken" :class="t.status === 'approved' && 'opacity-60'">
                <component :is="choreIcon(t.choreIcon)" v-if="t.kind === 'house'" class="size-4 text-sage" aria-hidden="true" />
                <span class="flex-1 font-medium" :class="t.status === 'approved' && 'line-through'">{{ t.title }}</span>
                <UAvatar :name="t.assigneeName" :color="t.assigneeColor" size="sm" />
                <span class="text-[13.5px]">{{ t.assigneeName }}</span>
              </RouterLink>
            </li>
            <li v-if="!d.tasks.length && !d.events.length" class="px-2 py-2 text-[13.5px] text-muted">لا شيء في هذا اليوم</li>
          </ul>
        </section>
      </div>
      <UEmpty v-if="days.every((d) => !d.tasks.length && !d.events.length)" :icon="CalendarDays" title="الأسبوع فارغ" :body="session.isManager ? 'أنشئ توزيع الأسبوع من تبويب «التوزيع».' : 'سيظهر هنا جدول المعسكر عند نشر التوزيع.'" />
    </template>
  </div>
</template>
