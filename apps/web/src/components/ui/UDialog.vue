<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { X } from 'lucide-vue-next';

const props = defineProps({ open: Boolean, title: { type: String, default: '' }, wide: Boolean });
const emit = defineEmits(['close']);
const panel = ref(null);
let lastFocus = null;

function onKey(e) {
  if (e.key === 'Escape') emit('close');
}

watch(
  () => props.open,
  async (open) => {
    if (open) {
      lastFocus = document.activeElement;
      document.addEventListener('keydown', onKey);
      document.body.style.overflow = 'hidden';
      await nextTick();
      const el = panel.value?.querySelector('input:not([type=hidden]):not([disabled]), textarea, select, button[data-autofocus]');
      (el || panel.value)?.focus({ preventScroll: true });
    } else {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
      lastFocus?.focus?.();
    }
  },
  { immediate: true },
);
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKey);
  document.body.style.overflow = '';
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      leave-active-class="transition duration-150 ease-in"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <div v-if="open" class="fixed inset-0 z-50 flex items-end justify-center bg-black/40 lg:items-center lg:p-6" @mousedown.self="emit('close')">
        <div
          ref="panel"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
          tabindex="-1"
          class="flex max-h-[92dvh] w-full flex-col rounded-t-[20px] bg-card shadow-xl outline-none lg:max-h-[86vh] lg:rounded-[16px]"
          :class="wide ? 'lg:max-w-3xl' : 'lg:max-w-lg'"
        >
          <div class="mx-auto mt-2 h-1 w-10 rounded-full bg-line lg:hidden" aria-hidden="true" />
          <header class="flex items-center justify-between gap-3 px-5 pb-2 pt-3 lg:pt-5">
            <h2 class="text-lg font-semibold">{{ title }}</h2>
            <button type="button" class="-me-2 grid size-9 place-items-center rounded-full text-muted hover:bg-sunken" aria-label="إغلاق" @click="emit('close')">
              <X class="size-5" />
            </button>
          </header>
          <div class="min-h-0 flex-1 overflow-y-auto px-5 pb-4">
            <slot />
          </div>
          <footer v-if="$slots.footer" class="safe-bottom flex gap-2 border-t border-line px-5 py-3">
            <slot name="footer" />
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
