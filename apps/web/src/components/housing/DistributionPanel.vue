<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { CircleAlert, RefreshCw, Send, Shuffle } from 'lucide-vue-next';
import { DAY_NAMES, SLOT_LABELS, addDays, adenDate, dayOfWeek, formatDate, weekStartOf } from '@camp/domain';
import { get, patch, post } from '../../lib/api.js';
import { ITEMS, POINTS, count } from '../../lib/format.js';
import { choreIcon } from '../../lib/icons.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import WeekNav from '../WeekNav.vue';
import UAvatar from '../ui/UAvatar.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UEmpty from '../ui/UEmpty.vue';
import USkeleton from '../ui/USkeleton.vue';

const props = defineProps({ initialWeek: { type: String, default: null } });
const session = useSession();
const ui = useUi();
const week = ref(props.initialWeek || weekStartOf(adenDate()));
const data = ref(null);
const busy = ref('');

async function load() {
  try {
    data.value = await get(`/distributions/${week.value}`);
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(week, () => {
  data.value = null;
  load();
});
watch(() => ui.versions.housing, load);

const status = computed(() => data.value?.distribution?.status || null);
const draft = computed(() => status.value === 'draft');
const editable = computed(() => session.isManager && draft.value);
const byDay = computed(() => {
  const map = new Map();
  for (const i of data.value?.items || []) map.set(i.date, [...(map.get(i.date) || []), i]);
  return [...map.entries()];
});
const maxPoints = computed(() => Math.max(1, ...(data.value?.summary || []).map((s) => s.points)));
const spread = computed(() => {
  const pts = (data.value?.summary || []).map((s) => s.points);
  return pts.length ? Math.max(...pts) - Math.min(...pts) : 0;
});

async function generate() {
  if (draft.value) {
    const ok = await ui.confirm({ title: 'إعادة التوزيع؟', body: 'ستُستبدل المسودة الحالية وتعديلاتك اليدوية عليها.', confirmLabel: 'إعادة التوزيع' });
    if (!ok) return;
  }
  busy.value = 'gen';
  try {
    data.value = await post(`/distributions/${week.value}/generate`);
    ui.toast('أُنشئت مسودة التوزيع. راجعها ثم انشرها');
  } catch (e) {
    ui.error(e);
  } finally {
    busy.value = '';
  }
}

async function assign(item, userId) {
  try {
    data.value = await patch(`/distribution-items/${item.id}`, { userId: userId ? Number(userId) : null });
  } catch (e) {
    ui.error(e);
    await load();
  }
}

async function publish() {
  const ok = await ui.confirm({
    title: 'نشر التوزيع؟',
    body: 'ستتحول كل بنود المسودة إلى مهام، ويصل لكل عضو إشعار بمهامه هذا الأسبوع.',
    confirmLabel: 'نشر للجميع',
  });
  if (!ok) return;
  busy.value = 'pub';
  try {
    data.value = await post(`/distributions/${week.value}/publish`);
    ui.toast('نُشر التوزيع ووصلت المهام للجميع');
    ui.bump('tasks', 'housing');
  } catch (e) {
    ui.error(e);
  } finally {
    busy.value = '';
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <WeekNav v-model="week" />
      <div class="flex items-center gap-2">
        <UBadge v-if="status" :tone="status === 'published' ? 'sage' : 'brass'">{{ status === 'published' ? 'منشور' : 'مسودة' }}</UBadge>
        <template v-if="session.isManager && status !== 'published'">
          <UButton variant="secondary" :icon="draft ? RefreshCw : Shuffle" :loading="busy === 'gen'" @click="generate">{{ draft ? 'إعادة التوزيع' : 'توزيع تلقائي' }}</UButton>
          <UButton v-if="draft" :icon="Send" :loading="busy === 'pub'" :disabled="data?.unassigned > 0" @click="publish">اعتماد ونشر</UButton>
        </template>
      </div>
    </div>

    <USkeleton v-if="!data" :lines="4" />
    <template v-else-if="data.distribution">
      <div v-if="data.unassigned" class="flex items-center gap-2 rounded-[12px] bg-danger-soft px-4 py-3 text-[14px] text-danger" role="alert">
        <CircleAlert class="size-5 shrink-0" />
        {{ count(data.unassigned, ITEMS) }} بلا مكلَّف لأن الجميع مشغول وقتها. أسندها يدوياً قبل النشر.
      </div>

      <!-- Points per member: equal shares at a glance -->
      <section class="section p-4 lg:p-5" aria-label="نقاط كل عضو هذا الأسبوع">
        <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
          <h3 class="font-semibold">النقاط هذا الأسبوع</h3>
          <p class="text-[13px] text-muted">الفرق بين الأعلى والأقل: <span class="num">{{ spread }}</span> نقاط · يُعوَّض الفرق في الأسابيع القادمة</p>
        </div>
        <ul class="grid gap-x-6 gap-y-2.5 sm:grid-cols-2">
          <li v-for="s in data.summary" :key="s.userId" class="flex items-center gap-3">
            <UAvatar :name="s.name" :color="s.color" size="sm" />
            <span class="w-20 shrink-0 truncate text-[14px]">{{ s.name }}</span>
            <span class="h-2 flex-1 overflow-hidden rounded-full bg-sunken"><span class="block h-full rounded-full bg-sage" :style="{ width: `${(s.points / maxPoints) * 100}%` }" /></span>
            <span class="num w-8 text-end font-semibold">{{ s.points }}</span>
          </li>
        </ul>
      </section>

      <section v-for="[date, items] in byDay" :key="date" class="section">
        <h3 class="px-4 pt-3 font-semibold lg:px-5">{{ DAY_NAMES[dayOfWeek(date)] }} <span class="num text-[13px] font-normal text-muted">{{ formatDate(date) }}</span></h3>
        <ul class="divide-y divide-line px-2 pb-1 lg:px-3">
          <li v-for="i in items" :key="i.id" class="flex flex-wrap items-center gap-3 px-2 py-2.5">
            <component :is="choreIcon(i.choreIcon)" class="size-5 shrink-0 text-sage" aria-hidden="true" />
            <span class="min-w-0 flex-1">
              <span class="font-medium">{{ i.choreName }}</span>
              <span class="ms-2 text-[13px] text-muted">{{ SLOT_LABELS[i.slot] }} · <span class="num">{{ count(i.points, POINTS) }}</span></span>
            </span>
            <select
              v-if="editable"
              class="input !min-h-9 w-40 !py-1.5"
              :value="i.userId ?? ''"
              :aria-label="`المكلَّف بـ ${i.choreName}`"
              :aria-invalid="i.userId == null || undefined"
              @change="assign(i, $event.target.value)"
            >
              <option value="">— بلا مكلَّف —</option>
              <option v-for="m in session.activeMembers" :key="m.id" :value="m.id">{{ m.name }}</option>
            </select>
            <span v-else class="flex items-center gap-2 text-[14px]">
              <UAvatar :name="i.userName || '؟'" :color="i.userColor" size="sm" />{{ i.userName || 'بلا مكلَّف' }}
            </span>
          </li>
        </ul>
      </section>
    </template>
    <UEmpty
      v-else
      :icon="Shuffle"
      title="لا يوجد توزيع لهذا الأسبوع"
      :body="session.isManager ? 'اضغط «توزيع تلقائي» لتوزيع مهام السكن بالتساوي مع مراعاة جدول كل فرد وغيابه.' : 'سيظهر التوزيع هنا عندما ينشره المدير.'"
    />
  </div>
</template>
