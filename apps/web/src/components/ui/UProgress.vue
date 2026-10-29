<script setup>
defineProps({ value: { type: Number, default: 0 }, tone: { type: String, default: 'sage' }, label: { type: String, default: '' } });
</script>
<template>
  <div class="h-2 w-full overflow-hidden rounded-full bg-sunken" role="progressbar" :aria-valuenow="Math.round(value)" aria-valuemin="0" aria-valuemax="100" :aria-label="label">
    <div class="h-full rounded-full transition-[width] duration-500" :class="tone === 'brass' ? 'bg-brass' : tone === 'danger' ? 'bg-danger' : 'bg-sage'" :style="{ width: `${Math.min(100, Math.max(0, value))}%` }" />
  </div>
</template>
