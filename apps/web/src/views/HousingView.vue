<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { addDays, adenDate, isDate, weekStartOf } from '@camp/domain';
import ChoresPanel from '../components/housing/ChoresPanel.vue';
import DistributionPanel from '../components/housing/DistributionPanel.vue';
import FairnessPanel from '../components/housing/FairnessPanel.vue';
import GroupSchedule from '../components/housing/GroupSchedule.vue';
import SwapsPanel from '../components/housing/SwapsPanel.vue';
import UTabs from '../components/ui/UTabs.vue';
import { useTab } from '../lib/useTab.js';

const route = useRoute();
const tabs = [
  { key: 'schedule', label: 'جدول المجموعة' },
  { key: 'distribution', label: 'التوزيع' },
  { key: 'chores', label: 'مهام السكن' },
  { key: 'fairness', label: 'لوحة العدالة' },
  { key: 'swaps', label: 'التبديل' },
];
const tab = useTab(tabs, 'schedule');
const week = computed(() => {
  if (isDate(route.query.week)) return weekStartOf(route.query.week);
  if (route.query.next === '1') return addDays(weekStartOf(adenDate()), 7);
  return null;
});
</script>

<template>
  <div class="space-y-5">
    <h1 class="hidden text-[26px] font-bold lg:block">السكن</h1>
    <UTabs v-model="tab" :tabs="tabs" />
    <GroupSchedule v-if="tab === 'schedule'" :initial-week="week" />
    <DistributionPanel v-else-if="tab === 'distribution'" :initial-week="week" />
    <ChoresPanel v-else-if="tab === 'chores'" />
    <FairnessPanel v-else-if="tab === 'fairness'" />
    <SwapsPanel v-else />
  </div>
</template>
