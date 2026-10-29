<script setup>
import { computed } from 'vue';
import { Check } from 'lucide-vue-next';
import { formatTime } from '@camp/domain';
import { PRAYERS, prayerTimes } from '../lib/prayers.js';

const props = defineProps({ date: { type: String, required: true }, done: { type: Array, default: () => [] }, now: { type: String, default: '' }, isToday: Boolean });
const emit = defineEmits(['toggle']);
const times = computed(() => prayerTimes(props.date));
const next = computed(() => (props.isToday ? PRAYERS.find((p) => times.value[p.key] > props.now)?.key : null));
</script>

<template>
  <ul class="grid grid-cols-5 gap-1.5">
    <li v-for="p in PRAYERS" :key="p.key">
      <button
        type="button"
        role="checkbox"
        :aria-checked="done.includes(p.key)"
        :aria-label="`${p.name} ${formatTime(times[p.key])}`"
        class="flex w-full flex-col items-center gap-1.5 rounded-[12px] py-2 transition-colors hover:bg-sunken"
        :class="next === p.key && !done.includes(p.key) && 'bg-brass-soft'"
        @click="emit('toggle', p.key)"
      >
        <span
          class="grid size-10 place-items-center rounded-full border-2 transition-colors"
          :class="done.includes(p.key) ? 'border-sage bg-sage text-white' : next === p.key ? 'border-brass text-[color:var(--brass)]' : 'border-line text-transparent'"
        >
          <Check class="size-4" stroke-width="3" />
        </span>
        <span class="text-[13px] font-medium">{{ p.name }}</span>
        <span class="num text-[11.5px] text-muted" :class="next === p.key && 'font-semibold !text-[color:var(--brass)]'">{{ formatTime(times[p.key]) }}</span>
      </button>
    </li>
  </ul>
</template>
