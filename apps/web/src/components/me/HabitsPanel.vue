<script setup>
import { onMounted, ref, watch } from 'vue';
import { Flame, Plus, Repeat } from 'lucide-vue-next';
import { DAY_NAMES, WEEK_ORDER, dayOfWeek } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useReorder } from '../../lib/useReorder.js';
import { useUi } from '../../stores/ui.js';
import ReorderArrows from '../ui/ReorderArrows.vue';
import RowActions from '../ui/RowActions.vue';
import UButton from '../ui/UButton.vue';
import UCheck from '../ui/UCheck.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const ui = useUi();
const habits = ref(null);
const today = ref('');
const archived = ref(false);
const formOpen = ref(false);
const editing = ref(null);
const { form, errors, saving, submit, reset } = useForm({ title: '', mode: 'daily', days: [] });

async function load() {
  try {
    const r = await get('/me/habits', { archived: archived.value ? 1 : undefined });
    habits.value = r.habits;
    today.value = r.today;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(archived, load);
const reorder = useReorder('habits', habits, load);

async function toggle(h) {
  const before = { ...h };
  h.doneToday = !h.doneToday;
  try {
    const r = await post(`/me/habits/${h.id}/toggle`, { done: h.doneToday });
    habits.value = habits.value.map((x) => (x.id === h.id ? r.habit : x));
    ui.bump('personal');
  } catch (e) {
    Object.assign(h, before);
    ui.error(e);
  }
}
function openForm(h = null) {
  editing.value = h;
  reset(h ? { title: h.title, mode: h.days === 'daily' ? 'daily' : 'days', days: h.days === 'daily' ? [] : [...h.days] } : { title: '', mode: 'daily', days: [] });
  formOpen.value = true;
}
async function save() {
  const body = { title: form.title, days: form.mode === 'daily' ? 'daily' : form.days };
  const r = await submit(() => (editing.value ? patch(`/me/habits/${editing.value.id}`, body) : post('/me/habits', body)));
  if (!r) return;
  formOpen.value = false;
  ui.toast(editing.value ? 'حُفظت العادة' : 'أُضيفت العادة');
  load();
}
async function run(h, key) {
  try {
    if (key === 'edit') openForm(h);
    else if (key === 'archive' || key === 'unarchive') {
      await post(`/me/habits/${h.id}/${key}`);
      ui.toast(key === 'archive' ? 'أُرشفت العادة' : 'أُعيدت من الأرشيف');
      load();
    } else if (key === 'delete') {
      if (await ui.confirm({ title: `حذف «${h.title}»؟`, body: 'يُحذف معها سجل الالتزام.', confirmLabel: 'حذف', danger: true })) {
        await ui.deleteWithUndo({ remove: () => del(`/me/habits/${h.id}`), restore: () => post(`/me/habits/${h.id}/restore`), message: 'حُذفت العادة', after: load });
      }
    }
  } catch (e) {
    ui.error(e);
  }
}
const dueToday = (h) => h.week.find((d) => d.date === today.value)?.due;
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <UButton variant="ghost" size="sm" :aria-pressed="archived" @click="archived = !archived">{{ archived ? 'العادات الحالية' : 'الأرشيف' }}</UButton>
      <UButton :icon="Plus" @click="openForm()">عادة</UButton>
    </div>
    <USkeleton v-if="!habits" :lines="3" />
    <section v-else-if="habits.length" class="section">
      <ul class="divide-y divide-line px-2">
        <li v-for="(h, i) in habits" :key="h.id" class="flex flex-wrap items-center gap-3 px-2 py-3">
          <ReorderArrows v-if="!archived" :first="i === 0" :last="i === habits.length - 1" @up="reorder.up(i)" @down="reorder.down(i)" />
          <UCheck size="lg" :checked="h.doneToday" :disabled="!dueToday(h) && !h.doneToday" :label="h.doneToday ? `${h.title}: تمّت اليوم` : `تمّت ${h.title} اليوم`" @toggle="toggle(h)" />
          <div class="min-w-0 flex-1">
            <p class="font-medium">{{ h.title }}</p>
            <p class="text-[13px] text-muted">
              {{ h.days === 'daily' ? 'يومياً' : h.days.map((d) => DAY_NAMES[d]).join('، ') }}
              <template v-if="!dueToday(h)">&nbsp;· ليست مستحقة اليوم</template>
            </p>
          </div>
          <ul class="flex gap-1" aria-label="هذا الأسبوع">
            <li
              v-for="d in h.week"
              :key="d.date"
              class="size-3 rounded-full"
              :class="d.done ? 'bg-sage' : d.due ? (d.date === today ? 'border-2 border-brass' : 'bg-line') : 'bg-sunken'"
              :title="`${DAY_NAMES[dayOfWeek(d.date)]}: ${d.done ? 'تمّت' : d.due ? 'لم تتم' : 'غير مستحقة'}`"
            />
          </ul>
          <span class="chip num bg-brass-soft text-[color:var(--brass)]" :title="'السلسلة الحالية'"><Flame class="size-3.5" />{{ h.streak }}</span>
          <RowActions :items="actions(['edit', archived ? 'unarchive' : 'archive', 'delete'])" @action="run(h, $event)" />
        </li>
      </ul>
      <p v-if="habits.some((h) => h.streak === 0 && !h.doneToday)" class="border-t border-line px-4 py-3 text-[13px] text-muted">انقطعت سلسلة؟ لا بأس، ابدأ من جديد اليوم.</p>
    </section>
    <UEmpty v-else :icon="Repeat" :title="archived ? 'لا عادات مؤرشفة' : 'لا عادات بعد'" body="أضف عادة تريد اكتسابها، وسجّلها بنقرة كل يوم." />

    <UDialog :open="formOpen" :title="editing ? 'تعديل العادة' : 'عادة جديدة'" @close="formOpen = false">
      <form id="habit-form" class="space-y-4" @submit.prevent="save">
        <UField v-slot="{ id, invalid }" label="العادة" :error="errors.title"><input :id="id" v-model="form.title" class="input" maxlength="80" :aria-invalid="invalid || undefined" placeholder="مثال: قراءة 10 صفحات" /></UField>
        <UField label="الأيام" :error="errors.days">
          <USegment
            v-model="form.mode"
            :options="[
              { value: 'daily', label: 'يومياً' },
              { value: 'days', label: 'أيام محددة' },
            ]"
            label="الأيام"
          />
          <div v-if="form.mode === 'days'" class="mt-2 flex flex-wrap gap-1.5">
            <button
              v-for="d in WEEK_ORDER"
              :key="d"
              type="button"
              :aria-pressed="form.days.includes(d)"
              class="h-9 rounded-full border px-3 text-[13.5px]"
              :class="form.days.includes(d) ? 'border-sage bg-sage-soft text-forest' : 'border-line'"
              @click="form.days = form.days.includes(d) ? form.days.filter((x) => x !== d) : [...form.days, d]"
            >
              {{ DAY_NAMES[d] }}
            </button>
          </div>
        </UField>
      </form>
      <template #footer>
        <UButton type="submit" form="habit-form" :loading="saving" :disabled="form.mode === 'days' && !form.days.length" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="formOpen = false">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
