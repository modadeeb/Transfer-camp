<script setup>
import BudgetPanel from '../components/money/BudgetPanel.vue';
import DebtsPanel from '../components/money/DebtsPanel.vue';
import ExpensesPanel from '../components/money/ExpensesPanel.vue';
import FundPanel from '../components/money/FundPanel.vue';
import UTabs from '../components/ui/UTabs.vue';
import { useTab } from '../lib/useTab.js';

const tabs = [
  { key: 'fund', label: 'الصندوق المشترك' },
  { key: 'expenses', label: 'المصروفات المشتركة' },
  { key: 'budget', label: 'أموالي' },
  { key: 'debts', label: 'الديون' },
];
const tab = useTab(tabs, 'fund');
</script>

<template>
  <div class="space-y-5">
    <h1 class="hidden text-[26px] font-bold lg:block">المال</h1>
    <UTabs v-model="tab" :tabs="tabs" />
    <FundPanel v-if="tab === 'fund'" />
    <ExpensesPanel v-else-if="tab === 'expenses'" />
    <BudgetPanel v-else-if="tab === 'budget'" />
    <DebtsPanel v-else />
  </div>
</template>
