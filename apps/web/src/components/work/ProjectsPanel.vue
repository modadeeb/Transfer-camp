<script setup>
import { onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { CircleCheckBig, FolderKanban, Plus } from 'lucide-vue-next';
import { formatDate } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useReorder } from '../../lib/useReorder.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import ReorderArrows from '../ui/ReorderArrows.vue';
import RowActions from '../ui/RowActions.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import UProgress from '../ui/UProgress.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const router = useRouter();
const projects = ref(null);
const archived = ref(false);
const formOpen = ref(false);
const editing = ref(null);
const STATUS = { active: ['نشط', 'sage'], on_hold: ['متوقف', 'brass'], closed: ['مغلق', 'neutral'] };
const { form, errors, saving, submit, reset } = useForm({ name: '', client: '', description: '', deadline: '', status: 'active' });

async function load() {
  try {
    projects.value = (await get('/projects', { archived: archived.value ? 1 : undefined })).projects;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(archived, load);
watch(() => ui.versions.tasks, load);
const reorder = useReorder('projects', projects, load);

function openForm(p = null) {
  editing.value = p;
  reset(p ? { name: p.name, client: p.client || '', description: p.description || '', deadline: p.deadline || '', status: p.status } : { name: '', client: '', description: '', deadline: '', status: 'active' });
  formOpen.value = true;
}
async function save() {
  const body = { ...form, client: form.client || null, description: form.description || null, deadline: form.deadline || null };
  const r = await submit(() => (editing.value ? patch(`/projects/${editing.value.id}`, body) : post('/projects', body)));
  if (!r) return;
  ui.toast(editing.value ? 'حُفظ المشروع' : 'أُضيف المشروع');
  formOpen.value = false;
  load();
}

function itemsFor(p) {
  if (!session.isManager) return actions(['view']);
  return actions(['view', 'edit', 'copy', archived.value ? 'unarchive' : 'archive', 'delete'], p.status !== 'closed' ? [{ key: 'close', label: 'إغلاق المشروع', icon: CircleCheckBig }] : []);
}
async function run(p, key) {
  try {
    if (key === 'view') router.push({ query: { tab: session.isManager ? 'manage' : 'board', project: p.id } });
    else if (key === 'edit') openForm(p);
    else if (key === 'copy') {
      await post(`/projects/${p.id}/copy`);
      ui.toast('نُسخ المشروع');
      load();
    } else if (key === 'archive' || key === 'unarchive') {
      await post(`/projects/${p.id}/${key}`);
      ui.toast(key === 'archive' ? 'أُرشف المشروع' : 'أُعيد من الأرشيف');
      load();
    } else if (key === 'close') {
      await patch(`/projects/${p.id}`, { status: 'closed' });
      ui.toast('أُغلق المشروع');
      load();
    } else if (key === 'delete') {
      const ok = await ui.confirm({ title: `حذف «${p.name}»؟`, body: 'تبقى مهامه موجودة بدون مشروع. يمكن الاستعادة خلال 30 يوماً.', confirmLabel: 'حذف', danger: true });
      if (ok) await ui.deleteWithUndo({ remove: () => del(`/projects/${p.id}`), restore: () => post(`/projects/${p.id}/restore`), message: 'حُذف المشروع', after: load });
    }
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <UButton variant="ghost" size="sm" :aria-pressed="archived" @click="archived = !archived">{{ archived ? 'المشاريع الحالية' : 'الأرشيف' }}</UButton>
      <UButton v-if="session.isManager" :icon="Plus" @click="openForm()">مشروع</UButton>
    </div>
    <USkeleton v-if="!projects" />
    <div v-else-if="projects.length" class="grid gap-3 md:grid-cols-2">
      <article v-for="(p, i) in projects" :key="p.id" class="section flex gap-3 p-4">
        <ReorderArrows v-if="session.isManager && !archived" :first="i === 0" :last="i === projects.length - 1" @up="reorder.up(i)" @down="reorder.down(i)" />
        <div class="min-w-0 flex-1 space-y-2">
          <div class="flex items-start gap-2">
            <div class="min-w-0 flex-1">
              <h3 class="font-semibold">{{ p.name }}</h3>
              <p class="text-[13px] text-muted">{{ p.client || 'بدون عميل' }}<template v-if="p.deadline">&nbsp;· التسليم {{ formatDate(p.deadline) }}</template></p>
            </div>
            <UBadge :tone="STATUS[p.status][1]">{{ STATUS[p.status][0] }}</UBadge>
            <RowActions :items="itemsFor(p)" menu-only @action="run(p, $event)" />
          </div>
          <p v-if="p.description" class="line-clamp-2 text-[14px] text-muted">{{ p.description }}</p>
          <div class="flex items-center gap-3">
            <UProgress :value="p.taskCount ? (p.doneCount / p.taskCount) * 100 : 0" :label="`تقدم ${p.name}`" />
            <span class="num shrink-0 text-[13px] text-muted">{{ p.doneCount }}/{{ p.taskCount }} مهام</span>
          </div>
        </div>
      </article>
    </div>
    <UEmpty v-else :icon="FolderKanban" title="لا توجد مشاريع" :body="session.isManager ? 'أضف مشاريع الشركة لتجمع مهامها وتتابع تقدمها.' : ''" />

    <UDialog :open="formOpen" :title="editing ? 'تعديل المشروع' : 'مشروع جديد'" @close="formOpen = false">
      <form id="project-form" class="space-y-4" @submit.prevent="save">
        <UField v-slot="{ id, invalid }" label="اسم المشروع" :error="errors.name"><input :id="id" v-model="form.name" class="input" maxlength="80" :aria-invalid="invalid || undefined" /></UField>
        <div class="grid grid-cols-2 gap-4">
          <UField v-slot="{ id }" label="العميل" optional :error="errors.client"><input :id="id" v-model="form.client" class="input" maxlength="80" /></UField>
          <UField v-slot="{ id }" label="موعد التسليم" optional :error="errors.deadline"><input :id="id" v-model="form.deadline" type="date" class="input" /></UField>
        </div>
        <UField v-slot="{ id }" label="الوصف" optional><textarea :id="id" v-model="form.description" class="input" maxlength="2000" /></UField>
        <UField label="الحالة">
          <USegment v-model="form.status" :options="Object.entries(STATUS).map(([value, [label]]) => ({ value, label }))" label="الحالة" />
        </UField>
      </form>
      <template #footer>
        <UButton type="submit" form="project-form" :loading="saving" class="flex-1">{{ editing ? 'حفظ' : 'إضافة' }}</UButton>
        <UButton variant="secondary" @click="formOpen = false">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
