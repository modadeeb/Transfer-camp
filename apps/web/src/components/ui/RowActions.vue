<script setup>
import { computed } from 'vue';
import { useUi } from '../../stores/ui.js';
import UMenu from './UMenu.vue';

// Laptop: view/edit/delete as icons in the row, the rest under ⋯. Phone: everything under ⋯.
const props = defineProps({ items: { type: Array, required: true }, menuOnly: Boolean });
const emit = defineEmits(['action']);
const ui = useUi();
const inline = computed(() => (ui.isDesktop && !props.menuOnly ? props.items.filter((i) => i.primary) : []));
const rest = computed(() => props.items.filter((i) => !inline.value.includes(i)));
</script>

<template>
  <div v-if="items.length" class="flex shrink-0 items-center" @click.stop>
    <button
      v-for="item in inline"
      :key="item.key"
      type="button"
      class="grid size-9 place-items-center rounded-full hover:bg-sunken"
      :class="item.danger ? 'text-danger/80 hover:text-danger' : 'text-muted hover:text-ink'"
      :aria-label="item.label"
      :title="item.label"
      @click="emit('action', item.key)"
    >
      <component :is="item.icon" class="size-[18px]" aria-hidden="true" />
    </button>
    <UMenu v-if="rest.length" :items="rest" @select="emit('action', $event)" />
  </div>
</template>
