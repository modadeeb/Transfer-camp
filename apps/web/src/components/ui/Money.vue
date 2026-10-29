<script setup>
import { computed } from 'vue';
import { formatMoney } from '@camp/domain';
import { useUi } from '../../stores/ui.js';
const props = defineProps({ amount: { type: Number, default: 0 }, unit: { type: Boolean, default: true }, signed: Boolean });
const ui = useUi();
const text = computed(() => {
  const s = formatMoney(props.amount, { unit: props.unit });
  return props.signed && props.amount > 0 ? `+${s}` : s;
});
</script>
<template>
  <span class="num whitespace-nowrap" :aria-label="ui.hideAmounts ? 'مبلغ مخفي' : undefined">{{ ui.hideAmounts ? '•••••' : text }}</span>
</template>
