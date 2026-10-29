<script setup>
defineProps({ icon: { type: [Object, Function], default: null }, title: { type: String, required: true }, body: { type: String, default: '' } });
</script>
<template>
  <div class="flex flex-col items-center px-6 py-10 text-center">
    <component :is="icon" v-if="icon" class="mb-3 size-9 text-sage" stroke-width="1.5" aria-hidden="true" />
    <p class="font-semibold">{{ title }}</p>
    <p v-if="body" class="mt-1 max-w-sm text-[14px] text-muted">{{ body }}</p>
    <div v-if="$slots.default" class="mt-4"><slot /></div>
  </div>
</template>
