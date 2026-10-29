<script setup>
import { computed, ref, watch } from 'vue';
import { adenDate } from '@camp/domain';
import { get, post } from '../../lib/api.js';
import { relativeDay } from '../../lib/format.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import MemberPicker from '../ui/MemberPicker.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';

const props = defineProps({ open: Boolean, taskId: { type: Number, default: null } });
const emit = defineEmits(['close', 'saved']);
const session = useSession();
const ui = useUi();
const myTasks = ref([]);
const theirTasks = ref([]);
const { form, errors, saving, submit, reset } = useForm({ taskId: null, toUserId: null, counterTaskId: null, note: '' });

watch(
  () => props.open,
  async (open) => {
    if (!open) return;
    reset({ taskId: props.taskId, toUserId: null, counterTaskId: null, note: '' });
    try {
      const r = await get('/tasks', { mine: 1, kind: 'house,company', status: 'pending,in_progress,returned', from: adenDate() });
      myTasks.value = r.tasks;
    } catch (e) {
      ui.error(e);
    }
  },
  { immediate: true },
);

const selected = computed(() => myTasks.value.find((t) => t.id === form.taskId));
watch(
  () => [form.toUserId, form.taskId],
  async () => {
    form.counterTaskId = null;
    theirTasks.value = [];
    if (!form.toUserId || !selected.value) return;
    const r = await get('/tasks', { assigneeId: form.toUserId, kind: selected.value.kind, status: 'pending,in_progress,returned', from: adenDate() }).catch(() => ({ tasks: [] }));
    theirTasks.value = r.tasks;
  },
);

async function save() {
  const r = await submit(() => post('/swaps', { taskId: form.taskId, toUserId: form.toUserId, counterTaskId: form.counterTaskId, note: form.note || null }));
  if (!r) return;
  ui.toast(`أُرسل الطلب إلى ${session.memberName(form.toUserId)}`);
  ui.bump('housing', 'tasks');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" title="طلب تبديل مهمة" @close="emit('close')">
    <form id="swap-form" class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id, invalid }" label="مهمتي" :error="errors.taskId">
        <select :id="id" v-model="form.taskId" class="input" :aria-invalid="invalid || undefined">
          <option :value="null" disabled>اختر مهمة</option>
          <option v-for="t in myTasks" :key="t.id" :value="t.id">{{ t.title }} — {{ relativeDay(t.dueDate) }}</option>
        </select>
        <p v-if="!myTasks.length" class="text-[13px] text-muted">لا توجد لديك مهام قادمة قابلة للتبديل.</p>
      </UField>
      <UField label="مع من؟" :error="errors.toUserId">
        <MemberPicker v-model="form.toUserId" :exclude="[session.user.id]" />
      </UField>
      <UField v-if="form.toUserId && selected" v-slot="{ id }" label="مقابل مهمة منه" optional hint="اتركها فارغة إن كنت تطلب أن يأخذ مهمتك فقط" :error="errors.counterTaskId">
        <select :id="id" v-model="form.counterTaskId" class="input">
          <option :value="null">بدون مقابل</option>
          <option v-for="t in theirTasks" :key="t.id" :value="t.id">{{ t.title }} — {{ relativeDay(t.dueDate) }}</option>
        </select>
      </UField>
      <UField v-slot="{ id }" label="رسالة" optional>
        <input :id="id" v-model="form.note" class="input" maxlength="300" placeholder="مثال: عندي اختبار ذلك اليوم" />
      </UField>
    </form>
    <template #footer>
      <UButton type="submit" form="swap-form" :loading="saving" :disabled="!form.taskId || !form.toUserId" class="flex-1">إرسال الطلب</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
