<script setup>
defineProps({ tone: { type: String, default: 'neutral' } });
const tones = {
  neutral: 'bg-sunken text-muted',
  sage: 'bg-sage-soft text-forest',
  brass: 'bg-brass-soft text-[color:var(--brass)]',
  danger: 'bg-danger-soft text-danger',
  solid: 'bg-primary text-on-primary',
};
</script>
<template>
  <span class="chip" :class="tones[tone]"><slot /></span>
</template>
