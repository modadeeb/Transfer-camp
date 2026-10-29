<script setup>
import { computed } from 'vue';
import EventsPanel from '../components/work/EventsPanel.vue';
import KanbanBoard from '../components/work/KanbanBoard.vue';
import ProjectsPanel from '../components/work/ProjectsPanel.vue';
import TaskList from '../components/work/TaskList.vue';
import UTabs from '../components/ui/UTabs.vue';
import { useTab } from '../lib/useTab.js';
import { useSession } from '../stores/session.js';

const session = useSession();
const tabs = computed(() => [
  { key: 'mine', label: 'مهامي' },
  { key: 'board', label: 'لوحة الفريق' },
  ...(session.isManager ? [{ key: 'manage', label: 'إدارة المهام' }] : []),
  { key: 'projects', label: 'المشاريع' },
  { key: 'events', label: 'الاجتماعات' },
]);
const tab = useTab(() => tabs.value, 'mine');
</script>

<template>
  <div class="space-y-5">
    <h1 class="hidden text-[26px] font-bold lg:block">العمل</h1>
    <UTabs v-model="tab" :tabs="tabs" />
    <TaskList v-if="tab === 'mine'" key="mine" mode="mine" kinds="house,company,personal" />
    <KanbanBoard v-else-if="tab === 'board'" />
    <TaskList v-else-if="tab === 'manage'" key="manage" mode="manage" />
    <ProjectsPanel v-else-if="tab === 'projects'" />
    <EventsPanel v-else />
  </div>
</template>
