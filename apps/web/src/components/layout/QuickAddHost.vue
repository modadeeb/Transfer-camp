<script setup>
import { ref, watch } from 'vue';
import { get } from '../../lib/api.js';
import { useUi } from '../../stores/ui.js';
import AbsenceForm from '../forms/AbsenceForm.vue';
import BudgetEntryForm from '../forms/BudgetEntryForm.vue';
import SharedExpenseForm from '../forms/SharedExpenseForm.vue';
import SwapForm from '../forms/SwapForm.vue';
import TaskForm from '../forms/TaskForm.vue';
import WeekStartForm from '../forms/WeekStartForm.vue';

// Personal expense/income need an open budget week; otherwise start one first.
const ui = useUi();
const budget = ref(null);
const needWeek = ref(false);

watch(
  () => ui.quickAdd,
  async (key) => {
    if (key !== 'personalExpense' && key !== 'income') return;
    try {
      budget.value = await get('/budget');
      if (!budget.value.week) {
        needWeek.value = true;
        ui.quickAdd = null;
      }
    } catch (e) {
      ui.error(e);
      ui.quickAdd = null;
    }
  },
);
const close = () => (ui.quickAdd = null);
</script>

<template>
  <TaskForm :open="ui.quickAdd === 'task'" @close="close" />
  <SharedExpenseForm :open="ui.quickAdd === 'sharedExpense'" @close="close" />
  <BudgetEntryForm :open="ui.quickAdd === 'personalExpense'" mode="expense" @close="close" />
  <BudgetEntryForm :open="ui.quickAdd === 'income'" mode="income" @close="close" />
  <SwapForm :open="ui.quickAdd === 'swap'" @close="close" />
  <AbsenceForm :open="ui.quickAdd === 'absence'" @close="close" />
  <WeekStartForm :open="needWeek" :current="budget" @close="needWeek = false" />
</template>
