<script setup>
defineProps({ modelValue: String, tabs: { type: Array, required: true } });
defineEmits(['update:modelValue']);
</script>

<template>
  <div role="tablist" class="scrollbar-none -mx-4 flex gap-1 overflow-x-auto px-4 lg:mx-0 lg:px-0">
    <button
      v-for="t in tabs"
      :key="t.key"
      role="tab"
      type="button"
      :aria-selected="modelValue === t.key"
      class="flex h-10 shrink-0 items-center gap-2 rounded-full px-4 text-[14.5px] transition-colors"
      :class="modelValue === t.key ? 'bg-primary text-on-primary' : 'text-muted hover:bg-sunken hover:text-ink'"
      @click="$emit('update:modelValue', t.key)"
    >
      {{ t.label }}
      <span v-if="t.count" class="num grid min-w-5 place-items-center rounded-full px-1.5 text-[12px]" :class="modelValue === t.key ? 'bg-white/20' : 'bg-brass-soft text-[color:var(--brass)]'">
        {{ t.count }}
      </span>
    </button>
  </div>
</template>
