<script setup>
import GoalsPanel from '../components/me/GoalsPanel.vue';
import HabitsPanel from '../components/me/HabitsPanel.vue';
import HealthPanel from '../components/me/HealthPanel.vue';
import MySchedule from '../components/me/MySchedule.vue';
import WorshipPanel from '../components/me/WorshipPanel.vue';
import UTabs from '../components/ui/UTabs.vue';
import { useTab } from '../lib/useTab.js';

const tabs = [
  { key: 'schedule', label: 'جدولي' },
  { key: 'worship', label: 'الصلوات' },
  { key: 'health', label: 'النوم والرياضة' },
  { key: 'goals', label: 'أهدافي' },
  { key: 'habits', label: 'عاداتي' },
];
const tab = useTab(tabs, 'schedule');
</script>

<template>
  <div class="space-y-5">
    <div class="hidden items-baseline gap-3 lg:flex">
      <h1 class="text-[26px] font-bold">أنا</h1>
      <p class="text-[14px] text-muted">مساحتك الخاصة؛ لا يراها أحد غيرك، ولا المدير.</p>
    </div>
    <UTabs v-model="tab" :tabs="tabs" />
    <MySchedule v-if="tab === 'schedule'" />
    <WorshipPanel v-else-if="tab === 'worship'" />
    <HealthPanel v-else-if="tab === 'health'" />
    <GoalsPanel v-else-if="tab === 'goals'" />
    <HabitsPanel v-else />
  </div>
</template>
