<script setup>
import { computed } from 'vue';
const props = defineProps({ name: { type: String, default: '' }, color: { type: String, default: '#56856A' }, size: { type: String, default: 'md' } });
const letter = computed(() => (props.name || '؟').trim().charAt(0));
</script>
<template>
  <span
    class="grid shrink-0 place-items-center rounded-full font-semibold text-white"
    :class="size === 'sm' ? 'size-6 text-[11px]' : size === 'lg' ? 'size-11 text-base' : 'size-8 text-[13px]'"
    :style="{ background: color || '#56856A' }"
    :title="name"
    aria-hidden="true"
  >{{ letter }}</span>
</template>
