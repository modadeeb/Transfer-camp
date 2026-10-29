<script setup>
import { nextTick, onBeforeUnmount, ref } from 'vue';
import { Ellipsis } from 'lucide-vue-next';

const props = defineProps({ items: { type: Array, required: true }, label: { type: String, default: 'المزيد من الإجراءات' } });
const emit = defineEmits(['select']);
const open = ref(false);
const root = ref(null);
const menu = ref(null);
const upward = ref(false);

function close() {
  open.value = false;
  document.removeEventListener('mousedown', outside);
  document.removeEventListener('keydown', onKey);
}
function outside(e) {
  if (!root.value?.contains(e.target)) close();
}
function onKey(e) {
  if (e.key === 'Escape') close();
  if (['ArrowDown', 'ArrowUp'].includes(e.key)) {
    e.preventDefault();
    const btns = [...(menu.value?.querySelectorAll('button') || [])];
    const i = btns.indexOf(document.activeElement);
    btns[(i + (e.key === 'ArrowDown' ? 1 : -1) + btns.length) % btns.length]?.focus();
  }
}
async function toggle() {
  if (open.value) return close();
  const rect = root.value.getBoundingClientRect();
  upward.value = window.innerHeight - rect.bottom < 260;
  open.value = true;
  document.addEventListener('mousedown', outside);
  document.addEventListener('keydown', onKey);
  await nextTick();
  menu.value?.querySelector('button')?.focus();
}
function pick(item) {
  close();
  emit('select', item.key);
}
onBeforeUnmount(close);
defineExpose({ toggle });
</script>

<template>
  <div ref="root" class="relative">
    <slot name="trigger" :toggle="toggle" :open="open">
      <button
        type="button"
        class="grid size-9 place-items-center rounded-full text-muted hover:bg-sunken hover:text-ink"
        :aria-label="props.label"
        :title="props.label"
        aria-haspopup="menu"
        :aria-expanded="open"
        @click.stop="toggle"
      >
        <Ellipsis class="size-5" />
      </button>
    </slot>
    <div
      v-if="open"
      ref="menu"
      role="menu"
      class="absolute end-0 z-40 min-w-44 overflow-hidden rounded-[12px] border border-line bg-card py-1 shadow-lg"
      :class="upward ? 'bottom-10' : 'top-10'"
    >
      <button
        v-for="item in items"
        :key="item.key"
        type="button"
        role="menuitem"
        class="flex w-full items-center gap-2.5 px-3.5 py-2.5 text-start text-[14.5px] hover:bg-sunken focus:bg-sunken focus:outline-none"
        :class="item.danger ? 'text-danger' : ''"
        @click.stop="pick(item)"
      >
        <component :is="item.icon" v-if="item.icon" class="size-4 shrink-0" aria-hidden="true" />
        {{ item.label }}
      </button>
    </div>
  </div>
</template>
