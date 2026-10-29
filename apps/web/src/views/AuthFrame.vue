<script setup>
import BrandMark from '../components/layout/BrandMark.vue';
defineProps({ title: { type: String, required: true }, subtitle: { type: String, default: '' } });
</script>
<template>
  <main class="safe-top grid min-h-dvh place-items-center px-4 py-10">
    <div class="w-full max-w-[400px]">
      <div class="mb-8 flex flex-col items-center text-center">
        <BrandMark :size="64" />
        <h1 class="mt-5 text-[26px] font-bold leading-tight">{{ title }}</h1>
        <p v-if="subtitle" class="mt-2 text-muted">{{ subtitle }}</p>
      </div>
      <div class="section p-5 sm:p-6"><slot /></div>
      <slot name="after" />
    </div>
  </main>
</template>
