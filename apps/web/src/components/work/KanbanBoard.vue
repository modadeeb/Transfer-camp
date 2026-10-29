<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { Flag } from 'lucide-vue-next';
import { adenDate, adenTime, isOverdue } from '@camp/domain';
import { get } from '../../lib/api.js';
import { relativeDay } from '../../lib/format.js';
import { useTaskActions } from '../../lib/useTaskActions.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import TaskDialogs from '../tasks/TaskDialogs.vue';
import RowActions from '../ui/RowActions.vue';
import UAvatar from '../ui/UAvatar.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const tasks = ref(null);
const projects = ref([]);
const route = useRoute();
const projectId = ref(typeof route.query.project === 'string' ? Number(route.query.project) : '');
const member = ref('');
const dragging = ref(null);
const over = ref(null);
const ta = useTaskActions(() => load());

const COLUMNS = [
  { key: 'pending', label: 'قيد الانتظار', statuses: ['pending', 'returned'] },
  { key: 'in_progress', label: 'قيد العمل', statuses: ['in_progress'] },
  { key: 'submitted', label: 'مراجعة', statuses: ['submitted'] },
  { key: 'approved', label: 'منجزة', statuses: ['approved'] },
];

async function load() {
  try {
    tasks.value = (await get('/tasks', { kind: 'company', projectId: projectId.value || undefined, assigneeId: member.value || undefined })).tasks;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(async () => {
  load();
  projects.value = (await get('/projects').catch(() => ({ projects: [] }))).projects;
});
watch([projectId, member], load);
watch(() => ui.versions.tasks, load);

const columns = computed(() => COLUMNS.map((c) => ({ ...c, items: (tasks.value || []).filter((t) => c.statuses.includes(t.status)) })));
const today = adenDate();
const now = adenTime();

async function drop(column) {
  const t = dragging.value;
  dragging.value = null;
  over.value = null;
  if (!t || column.statuses.includes(t.status)) return;
  await ta.act(t, 'set', { status: column.key });
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex flex-wrap gap-2">
      <select v-model="projectId" class="input w-auto" aria-label="المشروع">
        <option value="">كل المشاريع</option>
        <option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select>
      <select v-model="member" class="input w-auto" aria-label="العضو">
        <option value="">كل الفريق</option>
        <option v-for="m in session.activeMembers" :key="m.id" :value="m.id">{{ m.name }}</option>
      </select>
      <p v-if="session.isManager" class="hidden self-center text-[13px] text-muted lg:block">اسحب البطاقة بين الأعمدة لتغيير حالتها.</p>
    </div>
    <USkeleton v-if="!tasks" :lines="4" />
    <div v-else class="scrollbar-none -mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2 lg:mx-0 lg:grid lg:grid-cols-4 lg:overflow-visible lg:px-0">
      <section
        v-for="col in columns"
        :key="col.key"
        class="w-[82vw] max-w-sm shrink-0 snap-start rounded-[14px] bg-sunken p-2 transition-colors lg:w-auto lg:max-w-none"
        :class="over === col.key && 'ring-2 ring-sage'"
        :aria-label="col.label"
        @dragover.prevent="session.isManager && (over = col.key)"
        @dragleave="over = null"
        @drop.prevent="drop(col)"
      >
        <h3 class="flex items-center justify-between px-2 py-2 font-semibold">
          {{ col.label }} <span class="num text-[13px] font-normal text-muted">{{ col.items.length }}</span>
        </h3>
        <ul class="space-y-2">
          <li
            v-for="t in col.items"
            :key="t.id"
            class="rounded-[10px] border border-line bg-card p-3"
            :draggable="session.isManager"
            @dragstart="dragging = t"
            @dragend="(dragging = null), (over = null)"
          >
            <div class="flex items-start gap-2">
              <RouterLink :to="`/task/${t.id}`" class="min-w-0 flex-1 font-medium leading-snug">{{ t.title }}</RouterLink>
              <RowActions :items="ta.items(t)" menu-only @action="ta.run(t, $event)" />
            </div>
            <p v-if="t.projectName" class="mt-1 text-[12.5px] text-muted">{{ t.projectName }}</p>
            <div class="mt-2 flex flex-wrap items-center gap-2 text-[12.5px]">
              <span class="flex items-center gap-1.5"><UAvatar :name="t.assigneeName || '؟'" :color="t.assigneeColor" size="sm" />{{ t.assigneeName || 'بلا مكلَّف' }}</span>
              <span v-if="t.dueDate" class="num" :class="isOverdue(t, today, now) ? 'text-danger' : 'text-muted'">{{ relativeDay(t.dueDate) }}</span>
              <Flag v-if="t.priority === 'urgent'" class="size-3.5 text-danger" aria-label="عاجلة" />
              <span v-if="t.status === 'returned'" class="chip bg-brass-soft text-[color:var(--brass)]">مُعادة</span>
              <span class="num ms-auto text-muted">{{ t.size }} س</span>
            </div>
          </li>
          <li v-if="!col.items.length" class="px-2 py-4 text-center text-[13px] text-muted">لا شيء</li>
        </ul>
      </section>
    </div>
    <TaskDialogs :ta="ta" />
  </div>
</template>
