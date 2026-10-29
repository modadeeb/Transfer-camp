<script setup>
import { useUi } from '../../stores/ui.js';
import UButton from './UButton.vue';
import UDialog from './UDialog.vue';
const ui = useUi();
</script>

<template>
  <UDialog :open="Boolean(ui.confirmState)" :title="ui.confirmState?.title || ''" @close="ui.resolveConfirm(false)">
    <p v-if="ui.confirmState?.body" class="text-muted">{{ ui.confirmState.body }}</p>
    <template #footer>
      <UButton :variant="ui.confirmState?.danger ? 'danger' : 'primary'" data-autofocus class="flex-1" @click="ui.resolveConfirm(true)">{{ ui.confirmState?.confirmLabel }}</UButton>
      <UButton variant="secondary" class="flex-1" @click="ui.resolveConfirm(false)">إلغاء</UButton>
    </template>
  </UDialog>
</template>
