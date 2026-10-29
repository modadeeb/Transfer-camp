<script setup>
import { onMounted, ref, watch } from 'vue';
import { Flag, Plus, Target, X } from 'lucide-vue-next';
import { formatMonth } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { GOAL_CATEGORIES } from '../../lib/format.js';
import { useForm } from '../../lib/useForm.js';
import { useReorder } from '../../lib/useReorder.js';
import { useUi } from '../../stores/ui.js';
import ReorderArrows from '../ui/ReorderArrows.vue';
import RowActions from '../ui/RowActions.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UCheck from '../ui/UCheck.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import UProgress from '../ui/UProgress.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const ui = useUi();
const goals = ref(null);
const archived = ref(false);
const formOpen = ref(false);
const editing = ref(null);
const newStep = ref({});
const { form, errors, saving, submit, reset } = useForm({ title: '', category: 'personal', targetMonth: '', steps: [''] });

async function load() {
  try {
    goals.value = (await get('/me/goals', { archived: archived.value ? 1 : undefined })).goals;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(archived, load);
const reorder = useReorder('goals', goals, load);
const replace = (g) => (goals.value = goals.value.map((x) => (x.id === g.id ? g : x)));

function openForm(g = null) {
  editing.value = g;
  reset(g ? { title: g.title, category: g.category, targetMonth: g.targetDate ? g.targetDate.slice(0, 7) : '', steps: [] } : { title: '', category: 'personal', targetMonth: '', steps: [''] });
  formOpen.value = true;
}
async function save() {
  const body = { title: form.title, category: form.category, targetDate: form.targetMonth ? `${form.targetMonth}-01` : null };
  const r = await submit(() => (editing.value ? patch(`/me/goals/${editing.value.id}`, body) : post('/me/goals', { ...body, steps: form.steps.map((s) => s.trim()).filter(Boolean) })));
  if (!r) return;
  formOpen.value = false;
  ui.toast(editing.value ? 'حُفظ الهدف' : 'أُضيف الهدف');
  load();
}
async function toggleStep(g, s) {
  try {
    const r = await patch(`/me/goal-steps/${s.id}`, { done: !s.doneAt });
    replace(r.goal);
    if (r.goal.progress === 100) ui.toast('ما شاء الله! اكتمل الهدف');
  } catch (e) {
    ui.error(e);
  }
}
async function addStep(g) {
  const title = (newStep.value[g.id] || '').trim();
  if (!title) return;
  try {
    replace((await post(`/me/goals/${g.id}/steps`, { title })).goal);
    newStep.value[g.id] = '';
  } catch (e) {
    ui.error(e);
  }
}
async function removeStep(s) {
  try {
    replace((await del(`/me/goal-steps/${s.id}`)).goal);
  } catch (e) {
    ui.error(e);
  }
}
async function run(g, key) {
  try {
    if (key === 'edit') openForm(g);
    else if (key === 'archive' || key === 'unarchive') {
      await post(`/me/goals/${g.id}/${key}`);
      ui.toast(key === 'archive' ? 'أُرشف الهدف' : 'أُعيد من الأرشيف');
      load();
    } else if (key === 'delete') {
      if (await ui.confirm({ title: `حذف «${g.title}»؟`, confirmLabel: 'حذف', danger: true })) {
        await ui.deleteWithUndo({ remove: () => del(`/me/goals/${g.id}`), restore: () => post(`/me/goals/${g.id}/restore`), message: 'حُذف الهدف', after: load });
      }
    }
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <UButton variant="ghost" size="sm" :aria-pressed="archived" @click="archived = !archived">{{ archived ? 'الأهداف الحالية' : 'الأرشيف' }}</UButton>
      <UButton :icon="Plus" @click="openForm()">هدف</UButton>
    </div>
    <USkeleton v-if="!goals" :lines="3" />
    <div v-else-if="goals.length" class="grid gap-3 md:grid-cols-2">
      <article v-for="(g, i) in goals" :key="g.id" class="section flex gap-2 p-4">
        <ReorderArrows v-if="!archived" :first="i === 0" :last="i === goals.length - 1" @up="reorder.up(i)" @down="reorder.down(i)" />
        <div class="min-w-0 flex-1 space-y-3">
          <div class="flex items-start gap-2">
            <div class="min-w-0 flex-1">
              <h3 class="font-semibold">{{ g.title }}</h3>
              <p class="mt-1 flex flex-wrap gap-2 text-[13px] text-muted">
                <UBadge tone="sage">{{ GOAL_CATEGORIES[g.category] }}</UBadge>
                <span v-if="g.targetDate" class="inline-flex items-center gap-1"><Flag class="size-3.5" />{{ formatMonth(g.targetDate) }}</span>
              </p>
            </div>
            <RowActions :items="actions(['edit', archived ? 'unarchive' : 'archive', 'delete'])" menu-only @action="run(g, $event)" />
          </div>
          <div class="flex items-center gap-3"><UProgress :value="g.progress" :label="`تقدم ${g.title}`" /><span class="num text-[13px]">{{ g.progress }}%</span></div>
          <ul class="space-y-1">
            <li v-for="s in g.steps" :key="s.id" class="group flex items-center gap-2">
              <UCheck size="sm" :checked="Boolean(s.doneAt)" :label="s.title" @toggle="toggleStep(g, s)" />
              <span class="flex-1 text-[14.5px]" :class="s.doneAt && 'text-muted line-through'">{{ s.title }}</span>
              <button type="button" class="grid size-7 place-items-center rounded-full text-muted opacity-0 hover:text-danger focus:opacity-100 group-hover:opacity-100" :aria-label="`حذف ${s.title}`" @click="removeStep(s)"><X class="size-3.5" /></button>
            </li>
          </ul>
          <form class="flex gap-2" @submit.prevent="addStep(g)">
            <input v-model="newStep[g.id]" class="input !min-h-9 !py-1.5" placeholder="خطوة جديدة" :aria-label="`خطوة جديدة في ${g.title}`" />
            <UButton type="submit" size="sm" variant="soft">إضافة</UButton>
          </form>
        </div>
      </article>
    </div>
    <UEmpty v-else :icon="Target" :title="archived ? 'لا أهداف مؤرشفة' : 'لا أهداف بعد'" body="قسّم الهدف إلى خطوات صغيرة، فيُحسب التقدم منها." />

    <UDialog :open="formOpen" :title="editing ? 'تعديل الهدف' : 'هدف جديد'" @close="formOpen = false">
      <form id="goal-form" class="space-y-4" @submit.prevent="save">
        <UField v-slot="{ id, invalid }" label="الهدف" :error="errors.title"><input :id="id" v-model="form.title" class="input" maxlength="100" :aria-invalid="invalid || undefined" placeholder="مثال: إنهاء مشروع التخرج" /></UField>
        <UField label="التصنيف"><USegment v-model="form.category" :options="Object.entries(GOAL_CATEGORIES).map(([value, label]) => ({ value, label }))" label="التصنيف" /></UField>
        <UField v-slot="{ id }" label="الموعد المستهدف" optional :error="errors.targetDate"><input :id="id" v-model="form.targetMonth" type="month" class="input" /></UField>
        <UField v-if="!editing" label="الخطوات" optional>
          <div class="space-y-2">
            <input v-for="(s, i) in form.steps" :key="i" v-model="form.steps[i]" class="input" :placeholder="`الخطوة ${i + 1}`" :aria-label="`الخطوة ${i + 1}`" />
            <UButton variant="soft" size="sm" :icon="Plus" @click="form.steps.push('')">خطوة</UButton>
          </div>
        </UField>
      </form>
      <template #footer>
        <UButton type="submit" form="goal-form" :loading="saving" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="formOpen = false">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
