<script setup>
import { LoaderCircle } from 'lucide-vue-next';
const props = defineProps({
  variant: { type: String, default: 'primary' }, // primary | secondary | ghost | danger | soft
  size: { type: String, default: 'md' }, // md | sm | icon
  loading: Boolean,
  disabled: Boolean,
  type: { type: String, default: 'button' },
  icon: { type: [Object, Function], default: null },
  block: Boolean,
  label: { type: String, default: '' }, // accessible name for icon buttons
});
const variants = {
  primary: 'bg-primary text-on-primary hover:bg-primary-hover',
  secondary: 'bg-card text-ink border border-line hover:bg-sunken',
  ghost: 'text-ink hover:bg-sunken',
  danger: 'bg-danger text-white hover:opacity-90',
  soft: 'bg-sage-soft text-forest hover:brightness-95',
};
const sizes = { md: 'h-11 px-4 gap-2 text-[15px]', sm: 'h-9 px-3 gap-1.5 text-sm', icon: 'h-9 w-9 justify-center' };
</script>

<template>
  <button
    :type="type"
    :disabled="disabled || loading"
    :aria-label="label || undefined"
    :title="label || undefined"
    :aria-busy="loading || undefined"
    class="inline-flex shrink-0 items-center justify-center rounded-[10px] font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-55"
    :class="[variants[props.variant], sizes[props.size], block && 'w-full']"
  >
    <LoaderCircle v-if="loading" class="size-4 animate-spin" aria-hidden="true" />
    <component :is="icon" v-else-if="icon" class="size-[18px]" aria-hidden="true" />
    <slot />
  </button>
</template>
