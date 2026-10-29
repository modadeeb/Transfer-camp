<script setup>
import { computed } from 'vue';
import { ChevronLeft, ChevronRight } from 'lucide-vue-next';
import { addDays, adenDate, formatDate, weekStartOf } from '@camp/domain';
const props = defineProps({ modelValue: { type: String, required: true } });
const emit = defineEmits(['update:modelValue']);
const thisWeek = computed(() => weekStartOf(adenDate()));
const label = computed(() => {
  if (props.modelValue === thisWeek.value) return 'هذا الأسبوع';
  if (props.modelValue === addDays(thisWeek.value, 7)) return 'الأسبوع القادم';
  if (props.modelValue === addDays(thisWeek.value, -7)) return 'الأسبوع الماضي';
  return `أسبوع ${formatDate(props.modelValue)}`;
});
</script>
<template>
  <div class="flex items-center gap-1">
    <button type="button" class="grid size-9 place-items-center rounded-full hover:bg-sunken" aria-label="الأسبوع السابق" @click="emit('update:modelValue', addDays(modelValue, -7))">
      <ChevronRight class="size-5" />
    </button>
    <button type="button" class="min-w-32 rounded-full px-3 py-1.5 text-center text-[14.5px] font-medium hover:bg-sunken" :title="`${formatDate(modelValue)} – ${formatDate(addDays(modelValue, 6))}`" @click="emit('update:modelValue', thisWeek)">
      {{ label }}
      <span class="block text-[12px] font-normal text-muted">{{ formatDate(modelValue) }} – {{ formatDate(addDays(modelValue, 6)) }}</span>
    </button>
    <button type="button" class="grid size-9 place-items-center rounded-full hover:bg-sunken" aria-label="الأسبوع التالي" @click="emit('update:modelValue', addDays(modelValue, 7))">
      <ChevronLeft class="size-5" />
    </button>
  </div>
</template>
