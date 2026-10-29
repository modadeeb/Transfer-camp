<script setup>
defineProps({ lines: { type: Number, default: 3 } });
</script>
<template>
  <div class="space-y-3" aria-busy="true" aria-label="جارٍ التحميل">
    <div v-for="i in lines" :key="i" class="h-14 animate-pulse rounded-[10px] bg-sunken" />
  </div>
</template>
