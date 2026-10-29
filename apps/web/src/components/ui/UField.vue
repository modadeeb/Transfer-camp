<script setup>
import { computed, useId } from 'vue';
const props = defineProps({ label: String, error: String, hint: String, optional: Boolean });
const id = useId();
const describedBy = computed(() => (props.error ? `${id}-err` : props.hint ? `${id}-hint` : undefined));
</script>

<template>
  <div class="space-y-1.5">
    <label v-if="label" :for="id" class="block text-sm font-medium">
      {{ label }}
      <span v-if="optional" class="font-normal text-muted">(اختياري)</span>
    </label>
    <slot :id="id" :invalid="Boolean(error)" :described-by="describedBy" />
    <p v-if="error" :id="`${id}-err`" class="text-[13px] text-danger" role="alert">{{ error }}</p>
    <p v-else-if="hint" :id="`${id}-hint`" class="text-[13px] text-muted">{{ hint }}</p>
  </div>
</template>
