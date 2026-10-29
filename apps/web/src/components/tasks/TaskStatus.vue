<script setup>
import { computed } from 'vue';
import { STATUS_LABELS, adenDate, adenTime, isOverdue } from '@camp/domain';
import UBadge from '../ui/UBadge.vue';
const props = defineProps({ task: { type: Object, required: true } });
const overdue = computed(() => isOverdue(props.task, adenDate(), adenTime()));
const tone = computed(() => {
  if (overdue.value) return 'danger';
  return { approved: 'sage', submitted: 'brass', returned: 'brass', in_progress: 'solid', pending: 'neutral' }[props.task.status];
});
</script>
<template>
  <UBadge :tone="tone">{{ overdue ? 'متأخرة' : STATUS_LABELS[task.status] }}</UBadge>
</template>
