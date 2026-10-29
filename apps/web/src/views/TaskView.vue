<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ArrowRight, CircleCheck, ExternalLink, Flag, Play, RotateCcw, ThumbsUp } from 'lucide-vue-next';
import { KIND_LABELS, PRIORITY_LABELS, SPECIALTIES, formatDate, formatTime } from '@camp/domain';
import TaskDialogs from '../components/tasks/TaskDialogs.vue';
import TaskStatus from '../components/tasks/TaskStatus.vue';
import RowActions from '../components/ui/RowActions.vue';
import SectionCard from '../components/ui/SectionCard.vue';
import UAvatar from '../components/ui/UAvatar.vue';
import UButton from '../components/ui/UButton.vue';
import UCheck from '../components/ui/UCheck.vue';
import UEmpty from '../components/ui/UEmpty.vue';
import UField from '../components/ui/UField.vue';
import USkeleton from '../components/ui/USkeleton.vue';
import { get, post } from '../lib/api.js';
import { timeAgo } from '../lib/format.js';
import { useTaskActions } from '../lib/useTaskActions.js';
import { useUi } from '../stores/ui.js';

const route = useRoute();
const router = useRouter();
const ui = useUi();
const data = ref(null);
const missing = ref(false);
const note = ref('');
const url = ref('');
const acting = ref('');
const ta = useTaskActions((t) => (t ? (data.value.task = t) : load()));

async function load() {
  try {
    data.value = await get(`/tasks/${route.params.id}`);
    missing.value = false;
  } catch (e) {
    if (e.status === 404) missing.value = true;
    else ui.error(e);
  }
}
onMounted(load);
watch(() => route.params.id, load);
watch(() => ui.versions.tasks, load);

const t = computed(() => data.value?.task);
const open = computed(() => t.value && ['pending', 'in_progress', 'returned'].includes(t.value.status));
const ACTION_LABEL = {
  created: 'أُنشئت',
  updated: 'عُدّلت',
  start: 'بدأ العمل',
  submit: 'أُنجزت',
  approve: 'اعتُمدت',
  return: 'أُعيدت',
  undo: 'تراجع عن الإنجاز',
  set: 'تغيّرت الحالة',
  deleted: 'حُذفت',
  restored: 'استُعيدت',
  archived: 'أُرشفت',
  unarchived: 'أُعيدت من الأرشيف',
  swapped: 'نُقلت بالتبديل',
};

async function act(action) {
  acting.value = action;
  const body = action === 'submit' ? { note: note.value || null, url: url.value || undefined } : {};
  if (action === 'submit' && url.value && !/^https?:\/\//.test(url.value)) body.url = `https://${url.value}`;
  const r = await ta.act(t.value, action, body);
  if (r) {
    note.value = '';
    url.value = '';
    load();
  }
  acting.value = '';
}
async function toggleItem(item) {
  try {
    data.value.task = (await post(`/tasks/${t.value.id}/checklist`, { itemId: item.id, done: !item.done })).task;
  } catch (e) {
    ui.error(e);
  }
}
const canWork = computed(() => t.value && (ta.isAssignee(t.value) || ta.isApprover(t.value)));
const headerItems = computed(() => (t.value ? ta.items(t.value).filter((i) => !['view', 'start', 'submit', 'approve', 'return'].includes(i.key)) : []));
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5">
    <button type="button" class="inline-flex items-center gap-1 text-[14.5px] text-link" @click="router.back()"><ArrowRight class="size-4" />رجوع</button>
    <div v-if="missing" class="section"><UEmpty title="المهمة غير موجودة" body="ربما حُذفت أو ليست ضمن صلاحياتك." /></div>
    <USkeleton v-else-if="!data" :lines="5" />
    <template v-else>
      <header class="section p-5">
        <div class="flex items-start gap-3">
          <div class="min-w-0 flex-1">
            <p class="text-[13.5px] text-muted">{{ KIND_LABELS[t.kind] }}<template v-if="t.projectName">&nbsp;· {{ t.projectName }}</template></p>
            <h1 class="mt-1 text-[24px] font-bold leading-snug">{{ t.title }}</h1>
          </div>
          <TaskStatus :task="t" />
          <RowActions :items="headerItems" menu-only @action="ta.run(t, $event)" />
        </div>
        <dl class="mt-4 grid grid-cols-2 gap-3 text-[14px] sm:grid-cols-4">
          <div v-if="t.kind !== 'personal'">
            <dt class="text-muted">المكلَّف</dt>
            <dd class="mt-1 flex items-center gap-2 font-medium"><UAvatar :name="t.assigneeName || '؟'" :color="t.assigneeColor" size="sm" />{{ t.assigneeName || 'بلا مكلَّف' }}</dd>
          </div>
          <div>
            <dt class="text-muted">الموعد</dt>
            <dd class="num mt-1 font-medium">{{ t.dueDate ? formatDate(t.dueDate, { weekday: true }) : 'بلا موعد' }}<template v-if="t.dueTime">&nbsp;{{ formatTime(t.dueTime) }}</template></dd>
          </div>
          <div>
            <dt class="text-muted">الأولوية</dt>
            <dd class="mt-1 inline-flex items-center gap-1 font-medium" :class="t.priority === 'urgent' && 'text-danger'"><Flag v-if="t.priority !== 'normal'" class="size-4" />{{ PRIORITY_LABELS[t.priority] }}</dd>
          </div>
          <div v-if="t.kind !== 'personal'">
            <dt class="text-muted">{{ t.kind === 'house' ? 'النقاط' : 'الساعات' }}</dt>
            <dd class="num mt-1 font-medium">{{ t.size }}<template v-if="t.specialty">&nbsp;· {{ SPECIALTIES[t.specialty] }}</template></dd>
          </div>
        </dl>
      </header>

      <div v-if="t.status === 'returned' && t.returnNote" class="rounded-[12px] border border-brass/40 bg-brass-soft px-4 py-3">
        <p class="font-medium">ملاحظة المدير عند الإعادة</p>
        <p class="mt-1 whitespace-pre-line text-[14.5px]">{{ t.returnNote }}</p>
      </div>

      <SectionCard v-if="t.details" title="التفاصيل"><p class="whitespace-pre-line leading-7">{{ t.details }}</p></SectionCard>

      <SectionCard v-if="t.checklist.length" title="قائمة التحقق" :subtitle="`${t.checklist.filter((i) => i.done).length} من ${t.checklist.length}`">
        <ul class="space-y-2">
          <li v-for="item in t.checklist" :key="item.id" class="flex items-center gap-3">
            <UCheck size="sm" :checked="item.done" :disabled="!canWork" :label="item.text" @toggle="toggleItem(item)" />
            <span :class="item.done && 'text-muted line-through'">{{ item.text }}</span>
          </li>
        </ul>
      </SectionCard>

      <SectionCard v-if="t.attachments.length" title="المرفقات">
        <ul class="space-y-2">
          <li v-for="(a, i) in t.attachments" :key="i"><a :href="a.url" target="_blank" rel="noopener" class="inline-flex items-center gap-2 text-link underline" dir="auto"><ExternalLink class="size-4" />{{ a.label || a.url }}</a></li>
        </ul>
      </SectionCard>

      <SectionCard v-if="t.completionNote || t.completionUrl" title="ما أُنجز">
        <p v-if="t.completionNote" class="whitespace-pre-line">{{ t.completionNote }}</p>
        <a v-if="t.completionUrl" :href="t.completionUrl" target="_blank" rel="noopener" class="mt-2 inline-flex items-center gap-2 text-link underline"><ExternalLink class="size-4" />رابط العمل</a>
      </SectionCard>

      <!-- What can I do now -->
      <SectionCard v-if="canWork && (open || t.status === 'submitted')" :title="t.status === 'submitted' ? 'المراجعة' : 'إنجاز المهمة'">
        <div v-if="open" class="space-y-3">
          <template v-if="t.kind === 'company'">
            <UField v-slot="{ id }" label="ملاحظة للمدير" optional><textarea :id="id" v-model="note" class="input" maxlength="1000" placeholder="ماذا أنجزت؟" /></UField>
            <UField v-slot="{ id }" label="رابط العمل" optional><input :id="id" v-model="url" class="input" dir="ltr" placeholder="https://" /></UField>
          </template>
          <div class="flex flex-wrap gap-2">
            <UButton v-if="ta.isAssignee(t) && t.kind !== 'personal' && t.status !== 'in_progress'" variant="secondary" :icon="Play" :loading="acting === 'start'" @click="act('start')">بدء العمل</UButton>
            <UButton :icon="CircleCheck" :loading="acting === 'submit'" @click="act('submit')">{{ t.needsApproval && !ta.isApprover(t) ? 'أنجزت · أرسل للاعتماد' : 'أنجزت' }}</UButton>
          </div>
        </div>
        <div v-else-if="ta.isApprover(t)" class="flex flex-wrap gap-2">
          <UButton :icon="ThumbsUp" :loading="acting === 'approve'" @click="act('approve')">اعتماد</UButton>
          <UButton variant="secondary" :icon="RotateCcw" @click="ta.run(t, 'return')">إعادة بملاحظة</UButton>
        </div>
        <p v-else class="text-[14.5px] text-muted">أُرسلت للمدير وتنتظر اعتماده.</p>
      </SectionCard>

      <SectionCard title="السجل">
        <ol class="space-y-3 border-s-2 border-line ps-4">
          <li v-for="h in data.history" :key="h.id" class="relative">
            <span class="absolute -start-[1.4rem] top-2 size-2.5 rounded-full bg-sage" aria-hidden="true" />
            <p class="text-[14.5px]"><strong>{{ h.actorName || 'النظام' }}</strong> {{ ACTION_LABEL[h.action] || h.action }}<span v-if="h.details?.note" class="text-muted"> — {{ h.details.note }}</span></p>
            <p class="text-[12.5px] text-muted">{{ timeAgo(h.createdAt) }}</p>
          </li>
        </ol>
      </SectionCard>
    </template>
    <TaskDialogs :ta="ta" />
  </div>
</template>
