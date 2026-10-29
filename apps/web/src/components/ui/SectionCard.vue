<script setup>
defineProps({ title: { type: String, default: '' }, subtitle: { type: String, default: '' }, flush: Boolean });
</script>
<template>
  <section class="section">
    <header v-if="title || $slots.action" class="flex items-center justify-between gap-3 px-4 pt-4 lg:px-5">
      <div class="min-w-0">
        <h2 class="text-[16px] font-semibold">{{ title }}</h2>
        <p v-if="subtitle" class="text-[13px] text-muted">{{ subtitle }}</p>
      </div>
      <div class="flex shrink-0 items-center gap-1"><slot name="action" /></div>
    </header>
    <div :class="flush ? 'pt-2' : 'p-4 lg:p-5'"><slot /></div>
  </section>
</template>
