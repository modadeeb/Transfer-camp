<script setup>
import { computed } from 'vue';
import { useSession } from '../../stores/session.js';
import UAvatar from './UAvatar.vue';

// v-model: array of ids (multiple) or a single id / null.
const props = defineProps({ modelValue: { type: [Array, Number, null], default: null }, multiple: Boolean, exclude: { type: Array, default: () => [] }, label: { type: String, default: 'الأعضاء' } });
const emit = defineEmits(['update:modelValue']);
const session = useSession();
const options = computed(() => session.activeMembers.filter((m) => !props.exclude.includes(m.id)));
const selected = (id) => (props.multiple ? (props.modelValue || []).includes(id) : props.modelValue === id);
function toggle(id) {
  if (props.multiple) {
    const set = new Set(props.modelValue || []);
    set.has(id) ? set.delete(id) : set.add(id);
    emit('update:modelValue', options.value.map((m) => m.id).filter((x) => set.has(x)));
  } else emit('update:modelValue', props.modelValue === id ? null : id);
}
</script>

<template>
  <div class="flex flex-wrap gap-2" role="group" :aria-label="label">
    <button
      v-for="m in options"
      :key="m.id"
      type="button"
      :aria-pressed="selected(m.id)"
      class="flex h-10 items-center gap-2 rounded-full border pe-3 ps-1 text-[14px] transition-colors"
      :class="selected(m.id) ? 'border-sage bg-sage-soft text-forest' : 'border-line bg-card hover:border-sage'"
      @click="toggle(m.id)"
    >
      <UAvatar :name="m.name" :color="m.color" />
      {{ m.name }}
    </button>
  </div>
</template>
