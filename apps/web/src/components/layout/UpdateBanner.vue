<script setup>
import { onMounted, ref } from 'vue';
const waiting = ref(null);

onMounted(async () => {
  if (!('serviceWorker' in navigator) || import.meta.env.DEV) return;
  const { registerSW } = await import('virtual:pwa-register');
  const update = registerSW({
    onNeedRefresh() {
      waiting.value = update;
    },
  });
});
</script>

<template>
  <div v-if="waiting" class="fixed inset-x-4 top-4 z-[70] mx-auto flex max-w-md items-center gap-3 rounded-[12px] border border-line bg-card px-4 py-3 shadow-lg" role="status">
    <span class="flex-1 text-[14.5px]">يوجد تحديث جديد للتطبيق</span>
    <button type="button" class="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-on-primary" @click="waiting(true)">إعادة التحميل</button>
  </div>
</template>
