<script setup>
import { ref, watch } from 'vue';
import { Plus, Trash2 } from 'lucide-vue-next';
import { DAY_NAMES, WEEK_ORDER } from '@camp/domain';
import { put } from '../lib/api.js';
import { SLOT_KINDS } from '../lib/format.js';
import { useSession } from '../stores/session.js';
import { useUi } from '../stores/ui.js';
import UButton from './ui/UButton.vue';
import UDialog from './ui/UDialog.vue';

// Fixed weekly busy times (university / work) for one member.
const props = defineProps({ open: Boolean, userId: { type: Number, default: null }, slots: { type: Array, default: () => [] }, title: { type: String, default: 'أوقات الجامعة والعمل' } });
const emit = defineEmits(['close', 'saved']);
const session = useSession();
const ui = useUi();
const rows = ref([]);
const saving = ref(false);
watch(
  () => props.open,
  (open) => {
    if (open) rows.value = props.slots.map((s) => ({ dow: s.dow, startTime: s.startTime, endTime: s.endTime, kind: s.kind, label: s.label || '' }));
  },
  { immediate: true },
);
async function save() {
  saving.value = true;
  try {
    await put(`/members/${props.userId}/slots`, { slots: rows.value.map((s) => ({ ...s, label: s.label || null })) });
    ui.toast('حُفظ الجدول الثابت · يراعيه التوزيع القادم');
    await session.loadMembers();
    ui.bump('members');
    emit('saved');
    emit('close');
  } catch (e) {
    ui.error(e);
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <UDialog :open="open" :title="title" wide @close="emit('close')">
    <p class="mb-3 text-[14px] text-muted">أوقات ثابتة كل أسبوع. لا يُسند التوزيع مهام سكن خلالها.</p>
    <div class="space-y-2">
      <div v-for="(s, i) in rows" :key="i" class="grid grid-cols-2 gap-2 rounded-[12px] bg-sunken p-2 sm:grid-cols-[8rem_7rem_7rem_8rem_1fr_auto]">
        <select v-model.number="s.dow" class="input" :aria-label="`اليوم ${i + 1}`"><option v-for="d in WEEK_ORDER" :key="d" :value="d">{{ DAY_NAMES[d] }}</option></select>
        <input v-model="s.startTime" type="time" class="input" :aria-label="`من ${i + 1}`" />
        <input v-model="s.endTime" type="time" class="input" :aria-label="`إلى ${i + 1}`" />
        <select v-model="s.kind" class="input" :aria-label="`النوع ${i + 1}`"><option v-for="(label, key) in SLOT_KINDS" :key="key" :value="key">{{ label }}</option></select>
        <input v-model="s.label" class="input" placeholder="وصف (اختياري)" :aria-label="`الوصف ${i + 1}`" />
        <button type="button" class="grid size-11 place-items-center rounded-[10px] text-muted hover:text-danger" :aria-label="`حذف الوقت ${i + 1}`" @click="rows.splice(i, 1)"><Trash2 class="size-4" /></button>
      </div>
      <p v-if="!rows.length" class="text-[14px] text-muted">لا أوقات ثابتة بعد.</p>
    </div>
    <UButton variant="soft" size="sm" :icon="Plus" class="mt-3" @click="rows.push({ dow: 2, startTime: '08:00', endTime: '12:00', kind: 'university', label: '' })">إضافة وقت</UButton>
    <template #footer>
      <UButton :loading="saving" class="flex-1" @click="save">حفظ</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
