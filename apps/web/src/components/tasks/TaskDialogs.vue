<script setup>
import { ref, watch } from 'vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import SwapForm from '../forms/SwapForm.vue';
import TaskForm from '../forms/TaskForm.vue';

const props = defineProps({ ta: { type: Object, required: true } });
const note = ref('');
const saving = ref(false);
watch(
  () => props.ta.dialogs.returnTask,
  () => (note.value = ''),
);
async function sendReturn() {
  if (!note.value.trim()) return;
  saving.value = true;
  const t = props.ta.dialogs.returnTask;
  await props.ta.act(t, 'return', { note: note.value.trim() });
  saving.value = false;
  props.ta.dialogs.returnTask = null;
}
</script>

<template>
  <TaskForm :open="Boolean(ta.dialogs.edit)" :task="ta.dialogs.edit" @close="ta.dialogs.edit = null" />
  <SwapForm :open="ta.dialogs.swapOpen" :task-id="ta.dialogs.swapTaskId" @close="ta.dialogs.swapOpen = false" />
  <UDialog :open="Boolean(ta.dialogs.returnTask)" title="إعادة المهمة" @close="ta.dialogs.returnTask = null">
    <form id="return-form" @submit.prevent="sendReturn">
      <UField v-slot="{ id }" label="ما الذي يحتاج تعديلاً؟" :hint="ta.dialogs.returnTask?.title">
        <textarea :id="id" v-model="note" class="input" maxlength="1000" required />
      </UField>
    </form>
    <template #footer>
      <UButton type="submit" form="return-form" :loading="saving" :disabled="!note.trim()" class="flex-1">إعادة مع الملاحظة</UButton>
      <UButton variant="secondary" @click="ta.dialogs.returnTask = null">إلغاء</UButton>
    </template>
  </UDialog>
</template>
