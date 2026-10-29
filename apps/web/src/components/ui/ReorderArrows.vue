<script setup>
import { ChevronDown, ChevronUp } from 'lucide-vue-next';
defineProps({ first: Boolean, last: Boolean });
defineEmits(['up', 'down']);
</script>
<template>
  <div class="flex shrink-0 flex-col" @click.stop>
    <button type="button" class="grid h-5 w-7 place-items-center rounded text-muted hover:bg-sunken hover:text-ink disabled:opacity-25" :disabled="first" aria-label="تحريك للأعلى" title="تحريك للأعلى" @click="$emit('up')">
      <ChevronUp class="size-4" />
    </button>
    <button type="button" class="grid h-5 w-7 place-items-center rounded text-muted hover:bg-sunken hover:text-ink disabled:opacity-25" :disabled="last" aria-label="تحريك للأسفل" title="تحريك للأسفل" @click="$emit('down')">
      <ChevronDown class="size-4" />
    </button>
  </div>
</template>
