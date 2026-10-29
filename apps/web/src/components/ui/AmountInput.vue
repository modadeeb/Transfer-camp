<script setup>
import { computed } from 'vue';
const props = defineProps({ modelValue: { type: Number, default: null }, id: String, invalid: Boolean, describedBy: String, big: Boolean });
const emit = defineEmits(['update:modelValue']);
const shown = computed(() => (props.modelValue == null ? '' : props.modelValue.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')));
function onInput(e) {
  const digits = e.target.value.replace(/[٠-٩]/g, (d) => '٠١٢٣٤٥٦٧٨٩'.indexOf(d)).replace(/[^\d]/g, '').slice(0, 10);
  emit('update:modelValue', digits ? Number(digits) : null);
  e.target.value = digits ? digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',') : '';
}
</script>
<template>
  <div class="relative">
    <input
      :id="id"
      :value="shown"
      inputmode="numeric"
      autocomplete="off"
      dir="ltr"
      class="input num text-start"
      :class="big ? 'h-16 pr-14 text-[28px] font-semibold' : 'pr-12'"
      :aria-invalid="invalid || undefined"
      :aria-describedby="describedBy"
      placeholder="0"
      @input="onInput"
    />
    <span class="pointer-events-none absolute inset-y-0 right-3 grid place-items-center text-sm text-muted">ر.ي</span>
  </div>
</template>
