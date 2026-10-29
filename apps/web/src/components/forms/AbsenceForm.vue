<script setup>
import { watch } from 'vue';
import { addDays, adenDate } from '@camp/domain';
import { post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import MemberPicker from '../ui/MemberPicker.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';

const props = defineProps({ open: Boolean });
const emit = defineEmits(['close', 'saved']);
const session = useSession();
const ui = useUi();
const { form, errors, saving, submit, reset } = useForm({ userId: null, startDate: adenDate(), endDate: addDays(adenDate(), 2), reason: '' });
watch(
  () => props.open,
  (open) => open && reset({ userId: session.user.id, startDate: adenDate(), endDate: addDays(adenDate(), 2), reason: '' }),
  { immediate: true },
);

async function save() {
  const r = await submit(() => post('/absences', { userId: form.userId, startDate: form.startDate, endDate: form.endDate, reason: form.reason || null }));
  if (!r) return;
  ui.toast('سُجّل الغياب · لن تُسند مهام سكن في هذه الأيام عند التوزيع القادم');
  await session.loadMembers();
  ui.bump('members', 'housing');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" title="تسجيل غياب" @close="emit('close')">
    <form id="absence-form" class="space-y-4" @submit.prevent="save">
      <UField v-if="session.isManager" label="العضو">
        <MemberPicker v-model="form.userId" />
      </UField>
      <div class="grid grid-cols-2 gap-4">
        <UField v-slot="{ id, invalid }" label="من" :error="errors.startDate">
          <input :id="id" v-model="form.startDate" type="date" class="input" :aria-invalid="invalid || undefined" />
        </UField>
        <UField v-slot="{ id, invalid }" label="إلى" :error="errors.endDate">
          <input :id="id" v-model="form.endDate" type="date" class="input" :min="form.startDate" :aria-invalid="invalid || undefined" />
        </UField>
      </div>
      <UField v-slot="{ id }" label="السبب" optional>
        <input :id="id" v-model="form.reason" class="input" maxlength="120" placeholder="سفر، مرض…" />
      </UField>
      <p class="rounded-[10px] bg-sunken px-3 py-2 text-[13.5px] text-muted">يُعوَّض الفرق في النقاط لاحقاً، فالتوزيع يبقى عادلاً على المدى الطويل.</p>
    </form>
    <template #footer>
      <UButton type="submit" form="absence-form" :loading="saving" class="flex-1">تسجيل</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
