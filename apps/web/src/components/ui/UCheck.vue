<script setup>
import { Check } from 'lucide-vue-next';
defineProps({ checked: Boolean, label: { type: String, required: true }, size: { type: String, default: 'md' }, tone: { type: String, default: 'sage' }, disabled: Boolean });
defineEmits(['toggle']);
</script>

<template>
  <button
    type="button"
    role="checkbox"
    :aria-checked="checked"
    :aria-label="label"
    :title="label"
    :disabled="disabled"
    class="grid shrink-0 place-items-center rounded-full border-2 transition-colors disabled:opacity-50"
    :class="[
      size === 'lg' ? 'size-11' : size === 'sm' ? 'size-6' : 'size-8',
      checked ? (tone === 'brass' ? 'border-brass bg-brass text-white' : 'border-sage bg-sage text-white') : 'border-line bg-card text-transparent hover:border-sage',
    ]"
    @click="$emit('toggle')"
  >
    <Check :class="size === 'sm' ? 'size-3.5' : 'size-4'" stroke-width="3" />
  </button>
</template>
