<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { ChevronDown, Plus, Sparkles, X } from 'lucide-vue-next';
import { PRIORITY_LABELS, SPECIALTIES, adenDate } from '@camp/domain';
import { get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import MemberPicker from '../ui/MemberPicker.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';

const props = defineProps({ open: Boolean, task: { type: Object, default: null }, defaults: { type: Object, default: () => ({}) } });
const emit = defineEmits(['close', 'saved']);
const session = useSession();
const ui = useUi();
const projects = ref([]);
const more = ref(false);
const suggesting = ref(false);

const editing = computed(() => Boolean(props.task));
const blank = () => ({
  kind: session.isManager ? 'house' : 'personal',
  title: '',
  details: '',
  assigneeIds: [],
  assigneeId: null,
  projectId: null,
  specialty: null,
  dueDate: adenDate(),
  dueTime: '',
  priority: 'normal',
  size: 2,
  recurrence: 'none',
  needsApproval: null,
  checklist: [],
  attachments: [],
});
const { form, errors, saving, submit, reset } = useForm(blank());
const newItem = ref('');
const newLink = ref({ url: '', label: '' });

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    more.value = false;
    if (props.task) {
      const t = props.task;
      reset({
        ...blank(),
        kind: t.kind,
        title: t.title,
        details: t.details || '',
        assigneeId: t.assigneeId,
        projectId: t.projectId,
        specialty: t.specialty,
        dueDate: t.dueDate || '',
        dueTime: t.dueTime || '',
        priority: t.priority,
        size: t.size,
        recurrence: t.recurrence,
        needsApproval: t.needsApproval,
        checklist: t.checklist.map((i) => ({ ...i })),
        attachments: t.attachments.map((a) => ({ ...a })),
      });
      more.value = Boolean(t.details || t.checklist.length || t.attachments.length || t.recurrence !== 'none');
    } else reset({ ...blank(), ...props.defaults });
  },
  { immediate: true },
);

const kindOptions = computed(() =>
  session.isManager
    ? [
        { value: 'house', label: 'سكن' },
        { value: 'company', label: 'شركة' },
        { value: 'personal', label: 'شخصية' },
      ]
    : [{ value: 'personal', label: 'شخصية' }],
);
const shared = computed(() => form.kind !== 'personal');
const sizeLabel = computed(() => (form.kind === 'house' ? 'النقاط (الجهد من 1 إلى 5)' : 'الساعات المقدّرة'));
const approval = computed({
  get: () => (form.needsApproval === null ? form.kind === 'company' : form.needsApproval),
  set: (v) => (form.needsApproval = v),
});

onMounted(async () => {
  if (session.isManager) projects.value = (await get('/projects').catch(() => ({ projects: [] }))).projects;
});

watch(
  () => form.kind,
  (k) => {
    if (k === 'house' && form.size > 5) form.size = 3;
  },
);

async function suggest() {
  suggesting.value = true;
  try {
    const r = await get('/tasks/suggest', { kind: form.kind, specialty: form.specialty, date: form.dueDate });
    const pick = r.suggestions[0]?.userId;
    if (!pick) return ui.toast('لا يوجد أعضاء متاحون', { type: 'error' });
    if (editing.value) form.assigneeId = pick;
    else form.assigneeIds = [pick];
    ui.toast(`الاقتراح: ${session.memberName(pick)} (الأقل عبئاً${form.kind === 'company' && form.specialty ? ' في هذا التخصص' : ''})`);
  } catch (e) {
    ui.error(e);
  } finally {
    suggesting.value = false;
  }
}

function addItem() {
  const text = newItem.value.trim();
  if (!text) return;
  form.checklist.push({ text, done: false });
  newItem.value = '';
}
function addLink() {
  const url = newLink.value.url.trim();
  if (!url) return;
  form.attachments.push({ url: /^https?:\/\//.test(url) ? url : `https://${url}`, label: newLink.value.label.trim() || null });
  newLink.value = { url: '', label: '' };
}

async function save() {
  const payload = {
    title: form.title,
    details: form.details || null,
    dueDate: form.dueDate || null,
    dueTime: form.dueTime || null,
    priority: form.priority,
    size: Number(form.size) || 1,
    recurrence: form.recurrence,
    checklist: form.checklist,
    attachments: form.attachments,
  };
  if (shared.value) {
    payload.needsApproval = approval.value;
    if (form.kind === 'company') {
      payload.projectId = form.projectId || null;
      payload.specialty = form.specialty || null;
    }
  }
  const r = await submit(() => {
    if (editing.value) {
      if (shared.value) payload.assigneeId = form.assigneeId || null;
      return patch(`/tasks/${props.task.id}`, payload);
    }
    return post('/tasks', { ...payload, kind: form.kind, ...(shared.value ? { assigneeIds: form.assigneeIds, autoAssign: !form.assigneeIds.length } : {}) });
  });
  if (!r) return;
  ui.toast(editing.value ? 'حُفظت التعديلات' : r.tasks.length > 1 ? `أُضيفت ${r.tasks.length} مهام` : 'أُضيفت المهمة');
  ui.bump('tasks', 'housing');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" :title="editing ? 'تعديل المهمة' : 'مهمة جديدة'" wide @close="emit('close')">
    <form id="task-form" class="space-y-4" @submit.prevent="save">
      <UField v-if="!editing && kindOptions.length > 1" label="النوع">
        <USegment v-model="form.kind" :options="kindOptions" label="نوع المهمة" />
      </UField>

      <UField v-slot="{ id, invalid, describedBy }" label="المهمة" :error="errors.title">
        <input :id="id" v-model="form.title" class="input" maxlength="140" required :aria-invalid="invalid || undefined" :aria-describedby="describedBy" placeholder="مثال: تصميم شاشة الدخول" />
      </UField>

      <UField v-if="shared" :label="editing ? 'المكلَّف' : 'المكلَّفون'" :error="errors.assigneeIds || errors.assigneeId" :hint="!editing && !form.assigneeIds.length ? 'إن لم تختر أحداً، يُسنِدها النظام للأقل عبئاً' : ''">
        <div class="space-y-2">
          <MemberPicker v-if="editing" v-model="form.assigneeId" />
          <MemberPicker v-else v-model="form.assigneeIds" multiple />
          <UButton variant="soft" size="sm" :icon="Sparkles" :loading="suggesting" @click="suggest">اقترح بالتساوي</UButton>
        </div>
      </UField>

      <div v-if="form.kind === 'company'" class="grid gap-4 sm:grid-cols-2">
        <UField v-slot="{ id }" label="المشروع" optional :error="errors.projectId">
          <select :id="id" v-model="form.projectId" class="input">
            <option :value="null">بدون مشروع</option>
            <option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
        </UField>
        <UField v-slot="{ id }" label="التخصص المطلوب" optional>
          <select :id="id" v-model="form.specialty" class="input">
            <option :value="null">أي تخصص</option>
            <option v-for="(label, key) in SPECIALTIES" :key="key" :value="key">{{ label }}</option>
          </select>
        </UField>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <UField v-slot="{ id, invalid }" label="الموعد" :error="errors.dueDate">
          <input :id="id" v-model="form.dueDate" type="date" class="input" :aria-invalid="invalid || undefined" />
        </UField>
        <UField v-slot="{ id, invalid }" label="الوقت" optional :error="errors.dueTime">
          <input :id="id" v-model="form.dueTime" type="time" class="input" :aria-invalid="invalid || undefined" />
        </UField>
      </div>

      <UField label="الأولوية">
        <USegment v-model="form.priority" :options="Object.entries(PRIORITY_LABELS).map(([value, label]) => ({ value, label }))" label="الأولوية" />
      </UField>

      <UField v-if="shared" v-slot="{ id, invalid }" :label="sizeLabel" :error="errors.size">
        <input :id="id" v-model.number="form.size" type="number" min="1" :max="form.kind === 'house' ? 5 : 200" class="input num w-32" :aria-invalid="invalid || undefined" />
      </UField>

      <button type="button" class="flex items-center gap-1.5 text-[14.5px] font-medium text-link" :aria-expanded="more" @click="more = !more">
        <ChevronDown class="size-4 transition-transform" :class="more && 'rotate-180'" />
        خيارات إضافية
      </button>

      <div v-if="more" class="space-y-4 rounded-[12px] bg-sunken p-4">
        <UField v-slot="{ id }" label="التفاصيل" optional :error="errors.details">
          <textarea :id="id" v-model="form.details" class="input" maxlength="4000" placeholder="ما المطلوب بالضبط؟" />
        </UField>

        <UField label="قائمة تحقق" optional>
          <ul class="space-y-1.5">
            <li v-for="(item, i) in form.checklist" :key="i" class="flex items-center gap-2 rounded-[10px] bg-card px-3 py-2">
              <span class="flex-1">{{ item.text }}</span>
              <button type="button" class="grid size-7 place-items-center rounded-full text-muted hover:text-danger" :aria-label="`إزالة ${item.text}`" @click="form.checklist.splice(i, 1)">
                <X class="size-4" />
              </button>
            </li>
          </ul>
          <div class="mt-2 flex gap-2">
            <input v-model="newItem" class="input" placeholder="خطوة جديدة" aria-label="خطوة جديدة" @keydown.enter.prevent="addItem" />
            <UButton variant="secondary" :icon="Plus" label="إضافة خطوة" @click="addItem" />
          </div>
        </UField>

        <UField label="روابط ومرفقات" optional hint="ألصق رابط الملف (Google Drive أو Figma أو غيره)">
          <ul class="space-y-1.5">
            <li v-for="(a, i) in form.attachments" :key="i" class="flex items-center gap-2 rounded-[10px] bg-card px-3 py-2">
              <span class="min-w-0 flex-1 truncate" dir="auto">{{ a.label || a.url }}</span>
              <button type="button" class="grid size-7 place-items-center rounded-full text-muted hover:text-danger" aria-label="إزالة الرابط" @click="form.attachments.splice(i, 1)">
                <X class="size-4" />
              </button>
            </li>
          </ul>
          <div class="mt-2 grid gap-2 sm:grid-cols-[1fr_10rem_auto]">
            <input v-model="newLink.url" class="input" dir="ltr" placeholder="https://" aria-label="الرابط" />
            <input v-model="newLink.label" class="input" placeholder="الاسم" aria-label="اسم الرابط" />
            <UButton variant="secondary" @click="addLink">إضافة</UButton>
          </div>
          <p v-if="errors.attachments" class="text-[13px] text-danger">{{ errors.attachments }}</p>
        </UField>

        <UField v-slot="{ id }" label="التكرار">
          <select :id="id" v-model="form.recurrence" class="input">
            <option value="none">مرة واحدة</option>
            <option value="daily">يومياً</option>
            <option value="weekly">أسبوعياً</option>
          </select>
        </UField>

        <label v-if="shared" class="flex items-center justify-between gap-3">
          <span>
            <span class="block font-medium">تحتاج اعتمادي</span>
            <span class="text-[13px] text-muted">بعد أن يُنجزها العضو تصلك للمراجعة</span>
          </span>
          <input v-model="approval" type="checkbox" class="size-5 accent-[#56856A]" />
        </label>
      </div>
    </form>
    <template #footer>
      <UButton type="submit" form="task-form" :loading="saving" class="flex-1">{{ editing ? 'حفظ التعديلات' : 'إضافة المهمة' }}</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
