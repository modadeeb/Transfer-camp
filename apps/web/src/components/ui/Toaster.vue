<script setup>
import { CircleAlert, CircleCheck, X } from 'lucide-vue-next';
import { useUi } from '../../stores/ui.js';
const ui = useUi();
async function run(t) {
  ui.dismiss(t.id);
  try {
    await t.action.run();
    ui.toast('تمت الاستعادة');
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="pointer-events-none fixed inset-x-0 bottom-[calc(5.5rem+env(safe-area-inset-bottom))] z-[60] flex flex-col items-center gap-2 px-4 lg:bottom-6" aria-live="polite">
    <TransitionGroup enter-active-class="transition duration-200" enter-from-class="opacity-0 translate-y-2" leave-active-class="transition duration-150" leave-to-class="opacity-0">
      <div
        v-for="t in ui.toasts"
        :key="t.id"
        class="pointer-events-auto flex w-full max-w-md items-center gap-3 rounded-[12px] px-4 py-3 text-[14.5px] shadow-lg"
        :class="t.type === 'error' ? 'bg-danger text-white' : 'bg-[#243F35] text-[#F7F6F1]'"
        :role="t.type === 'error' ? 'alert' : 'status'"
      >
        <CircleAlert v-if="t.type === 'error'" class="size-5 shrink-0" />
        <CircleCheck v-else class="size-5 shrink-0 text-[#B68A47]" />
        <span class="flex-1">{{ t.message }}</span>
        <button v-if="t.action" type="button" class="rounded-md px-2 py-1 font-semibold text-[#E2C48E] hover:bg-white/10" @click="run(t)">{{ t.action.label }}</button>
        <button type="button" class="grid size-7 place-items-center rounded-full opacity-70 hover:opacity-100" aria-label="إغلاق التنبيه" @click="ui.dismiss(t.id)">
          <X class="size-4" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
