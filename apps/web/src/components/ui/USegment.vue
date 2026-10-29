<script setup>
defineProps({ modelValue: { type: [String, Number, Boolean, null], default: null }, options: { type: Array, required: true }, label: { type: String, default: '' } });
defineEmits(['update:modelValue']);
</script>
<template>
  <div class="flex flex-wrap gap-1.5" role="radiogroup" :aria-label="label">
    <button
      v-for="o in options"
      :key="String(o.value)"
      type="button"
      role="radio"
      :aria-checked="modelValue === o.value"
      class="flex h-10 items-center gap-1.5 rounded-full border px-4 text-[14px] transition-colors"
      :class="modelValue === o.value ? 'border-sage bg-sage-soft font-medium text-forest' : 'border-line bg-card text-ink hover:border-sage'"
      @click="$emit('update:modelValue', o.value)"
    >
      <component :is="o.icon" v-if="o.icon" class="size-4" aria-hidden="true" />
      {{ o.label }}
    </button>
  </div>
</template>
