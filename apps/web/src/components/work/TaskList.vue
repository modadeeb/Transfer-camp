<script setup>
// Filterable task list. Manager mode adds selection, bulk actions and ▲▼ ordering.
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { Archive, CalendarClock, ClipboardList, Plus, Search, Trash2, UserRoundCog } from 'lucide-vue-next';
import { STATUS_LABELS } from '@camp/domain';
import { get, post } from '../../lib/api.js';
import { TASKS, count } from '../../lib/format.js';
import { useReorder } from '../../lib/useReorder.js';
import { useTaskActions } from '../../lib/useTaskActions.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import TaskDialogs from '../tasks/TaskDialogs.vue';
import TaskRow from '../tasks/TaskRow.vue';
import MemberPicker from '../ui/MemberPicker.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import USkeleton from '../ui/USkeleton.vue';

const props = defineProps({ mode: { type: String, default: 'mine' }, kinds: { type: String, default: 'company' } }); // mode: mine | manage
const route = useRoute();
const session = useSession();
const ui = useUi();
const tasks = ref(null);
const projects = ref([]);
const selected = ref(new Set());
const bulk = reactive({ open: null, assigneeId: null, dueDate: '' });
const filters = reactive({
  q: '',
  kind: props.mode === 'manage' ? 'house,company' : props.kinds,
  assigneeId: '',
  status: typeof route.query.status === 'string' ? route.query.status : props.mode === 'mine' ? 'pending,in_progress,submitted,returned' : '',
  projectId: typeof route.query.project === 'string' ? Number(route.query.project) : '',
  overdue: route.query.overdue === '1',
  archived: false,
});
const manage = computed(() => props.mode === 'manage');
const ta = useTaskActions(() => load());

async function load() {
  try {
    const r = await get('/tasks', {
      kind: filters.kind,
      mine: manage.value ? undefined : 1,
      assigneeId: manage.value ? filters.assigneeId || undefined : undefined,
      status: filters.status || undefined,
      projectId: filters.projectId || undefined,
      q: filters.q || undefined,
      overdue: filters.overdue ? 1 : undefined,
      archived: filters.archived ? 1 : undefined,
    });
    tasks.value = r.tasks;
    selected.value = new Set([...selected.value].filter((id) => r.tasks.some((t) => t.id === id)));
  } catch (e) {
    ui.error(e);
  }
}
let timer;
watch(filters, () => {
  clearTimeout(timer);
  timer = setTimeout(load, 250);
});
watch(() => ui.versions.tasks, load);
onMounted(async () => {
  load();
  projects.value = (await get('/projects').catch(() => ({ projects: [] }))).projects;
});
const reorder = useReorder('tasks', tasks, load);

function toggleSel(id) {
  const s = new Set(selected.value);
  s.has(id) ? s.delete(id) : s.add(id);
  selected.value = s;
}
const allSelected = computed(() => tasks.value?.length && selected.value.size === tasks.value.length);
function selectAll() {
  selected.value = allSelected.value ? new Set() : new Set(tasks.value.map((t) => t.id));
}

async function runBulk(action) {
  const ids = [...selected.value];
  if (action === 'delete' && !(await ui.confirm({ title: `حذف ${ids.length} مهام؟`, body: 'المهام المنجزة تُؤرشف بدلاً من الحذف.', confirmLabel: 'حذف', danger: true }))) return;
  try {
    await post('/tasks/bulk', { ids, action, assigneeId: bulk.assigneeId || undefined, dueDate: bulk.dueDate || undefined });
    ui.toast({ delete: 'حُذفت المهام المحددة', archive: 'أُرشفت المهام المحددة', reassign: 'أُعيد الإسناد', reschedule: 'تغيّر الموعد' }[action]);
    selected.value = new Set();
    bulk.open = null;
    ui.bump('tasks', 'housing');
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-3">
    <!-- Filters -->
    <div class="flex flex-wrap items-center gap-2">
      <label class="relative min-w-44 flex-1">
        <span class="sr-only">بحث</span>
        <Search class="pointer-events-none absolute inset-y-0 start-3 my-auto size-4 text-muted" />
        <input v-model="filters.q" class="input ps-9" placeholder="ابحث في المهام" type="search" />
      </label>
      <select v-if="manage" v-model="filters.kind" class="input w-auto" aria-label="النوع">
        <option value="house,company">السكن والشركة</option>
        <option value="house">السكن</option>
        <option value="company">الشركة</option>
      </select>
      <select v-if="manage" v-model="filters.assigneeId" class="input w-auto" aria-label="العضو">
        <option value="">كل الأعضاء</option>
        <option v-for="m in session.activeMembers" :key="m.id" :value="m.id">{{ m.name }}</option>
      </select>
      <select v-model="filters.status" class="input w-auto" aria-label="الحالة">
        <option value="">كل الحالات</option>
        <option value="pending,in_progress,submitted,returned">غير المنجزة</option>
        <option v-for="(label, key) in STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
      </select>
      <select v-if="projects.length && filters.kind !== 'house'" v-model="filters.projectId" class="input w-auto" aria-label="المشروع">
        <option value="">كل المشاريع</option>
        <option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select>
      <label class="flex h-11 items-center gap-2 rounded-[10px] px-2 text-[14px]"><input v-model="filters.overdue" type="checkbox" class="size-4 accent-[#56856A]" />المتأخرة</label>
      <label v-if="manage" class="flex h-11 items-center gap-2 rounded-[10px] px-2 text-[14px]"><input v-model="filters.archived" type="checkbox" class="size-4 accent-[#56856A]" />المؤرشفة</label>
      <UButton v-if="manage" :icon="Plus" class="ms-auto" @click="ui.quickAdd = 'task'">مهمة</UButton>
    </div>

    <!-- Bulk bar -->
    <div v-if="manage && selected.size" class="sticky top-16 z-20 flex flex-wrap items-center gap-2 rounded-[12px] bg-primary px-3 py-2 text-on-primary lg:top-[4.5rem]">
      <span class="num px-2 font-medium">المحدد: {{ count(selected.size, TASKS) }}</span>
      <button type="button" class="flex h-9 items-center gap-1.5 rounded-lg px-3 hover:bg-white/10" @click="bulk.open = 'reassign'"><UserRoundCog class="size-4" />إعادة إسناد</button>
      <button type="button" class="flex h-9 items-center gap-1.5 rounded-lg px-3 hover:bg-white/10" @click="bulk.open = 'reschedule'"><CalendarClock class="size-4" />تغيير الموعد</button>
      <button type="button" class="flex h-9 items-center gap-1.5 rounded-lg px-3 hover:bg-white/10" @click="runBulk('archive')"><Archive class="size-4" />أرشفة</button>
      <button type="button" class="flex h-9 items-center gap-1.5 rounded-lg px-3 hover:bg-white/10" @click="runBulk('delete')"><Trash2 class="size-4" />حذف</button>
      <button type="button" class="ms-auto h-9 rounded-lg px-3 hover:bg-white/10" @click="selected = new Set()">إلغاء التحديد</button>
    </div>

    <USkeleton v-if="!tasks" />
    <section v-else-if="tasks.length" class="section">
      <div v-if="manage" class="flex items-center gap-3 border-b border-line px-4 py-2 text-[13px] text-muted">
        <input type="checkbox" class="size-4 accent-[#56856A]" :checked="allSelected" aria-label="تحديد الكل" @change="selectAll" />
        <span class="num">{{ count(tasks.length, TASKS) }}</span>
        <span class="ms-auto hidden sm:block">الترتيب بالأسهم هو ما يراه العضو أولاً</span>
      </div>
      <ul class="px-2 py-1">
        <TaskRow
          v-for="(t, i) in tasks"
          :key="t.id"
          :task="t"
          :ta="ta"
          :show-assignee="manage"
          :selectable="manage"
          :selected="selected.has(t.id)"
          :reorder="manage && !filters.archived"
          :first="i === 0"
          :last="i === tasks.length - 1"
          @select="toggleSel(t.id)"
          @up="reorder.up(i)"
          @down="reorder.down(i)"
        />
      </ul>
    </section>
    <UEmpty v-else :icon="ClipboardList" :title="manage ? 'لا توجد مهام بهذه الشروط' : 'لا مهام مفتوحة لك هنا'" :body="manage ? 'غيّر الفلاتر أو أضف مهمة جديدة.' : 'عندما يسند لك المدير مهمة ستظهر هنا ويصلك إشعار.'" />

    <UDialog :open="bulk.open === 'reassign'" title="إعادة إسناد المهام المحددة" @close="bulk.open = null">
      <MemberPicker v-model="bulk.assigneeId" />
      <template #footer>
        <UButton class="flex-1" :disabled="!bulk.assigneeId" @click="runBulk('reassign')">إعادة الإسناد</UButton>
        <UButton variant="secondary" @click="bulk.open = null">إلغاء</UButton>
      </template>
    </UDialog>
    <UDialog :open="bulk.open === 'reschedule'" title="موعد جديد للمهام المحددة" @close="bulk.open = null">
      <UField v-slot="{ id }" label="التاريخ"><input :id="id" v-model="bulk.dueDate" type="date" class="input" /></UField>
      <template #footer>
        <UButton class="flex-1" :disabled="!bulk.dueDate" @click="runBulk('reschedule')">تغيير الموعد</UButton>
        <UButton variant="secondary" @click="bulk.open = null">إلغاء</UButton>
      </template>
    </UDialog>
    <TaskDialogs :ta="ta" />
  </div>
</template>
