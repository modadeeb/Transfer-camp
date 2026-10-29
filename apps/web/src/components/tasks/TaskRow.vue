<script setup>
import { computed } from 'vue';
import { Briefcase, Flag, House, ListChecks, Repeat, UserRound } from 'lucide-vue-next';
import { formatTime } from '@camp/domain';
import { POINTS, count, relativeDay } from '../../lib/format.js';
import RowActions from '../ui/RowActions.vue';
import ReorderArrows from '../ui/ReorderArrows.vue';
import UAvatar from '../ui/UAvatar.vue';
import UCheck from '../ui/UCheck.vue';
import TaskStatus from './TaskStatus.vue';

const props = defineProps({
  task: { type: Object, required: true },
  ta: { type: Object, required: true },
  showAssignee: Boolean,
  showDate: { type: Boolean, default: true },
  reorder: Boolean,
  first: Boolean,
  last: Boolean,
  selectable: Boolean,
  selected: Boolean,
});
defineEmits(['up', 'down', 'select']);
const t = computed(() => props.task);
const done = computed(() => t.value.status === 'approved');
const canToggle = computed(() => props.ta.isAssignee(t.value) || props.ta.isApprover(t.value));
const kindIcon = { house: House, company: Briefcase, personal: UserRound };
const checklist = computed(() => {
  const list = t.value.checklist || [];
  return list.length ? `${list.filter((i) => i.done).length}/${list.length}` : null;
});
</script>

<template>
  <li class="flex items-center gap-3 rounded-[10px] px-2 py-2.5 hover:bg-sunken/60" :class="done && 'opacity-70'">
    <input v-if="selectable" type="checkbox" class="size-4 shrink-0 accent-[#56856A]" :checked="selected" :aria-label="`تحديد ${t.title}`" @change="$emit('select')" />
    <ReorderArrows v-if="reorder" :first="first" :last="last" @up="$emit('up')" @down="$emit('down')" />
    <UCheck
      :checked="done || t.status === 'submitted'"
      :tone="t.status === 'submitted' ? 'brass' : 'sage'"
      :disabled="!canToggle"
      :label="done ? `${t.title}: منجزة` : `إنجاز ${t.title}`"
      @toggle="ta.toggle(t)"
    />
    <RouterLink :to="`/task/${t.id}`" class="min-w-0 flex-1 rounded-md">
      <p class="truncate font-medium" :class="done && 'line-through decoration-muted'">{{ t.title }}</p>
      <p class="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-muted">
        <span class="inline-flex items-center gap-1"><component :is="kindIcon[t.kind]" class="size-3.5" aria-hidden="true" />{{ t.projectName || { house: 'سكن', company: 'شركة', personal: 'شخصية' }[t.kind] }}</span>
        <span v-if="showDate && (t.dueDate || t.dueTime)" class="num">{{ relativeDay(t.dueDate) }}{{ t.dueTime ? ` ${formatTime(t.dueTime)}` : '' }}</span>
        <span v-if="t.priority !== 'normal'" class="inline-flex items-center gap-1" :class="t.priority === 'urgent' ? 'text-danger' : 'text-[color:var(--brass)]'">
          <Flag class="size-3.5" aria-hidden="true" />{{ t.priority === 'urgent' ? 'عاجلة' : 'مهمة' }}
        </span>
        <span v-if="checklist" class="num inline-flex items-center gap-1"><ListChecks class="size-3.5" aria-hidden="true" />{{ checklist }}</span>
        <span v-if="t.recurrence !== 'none'" class="inline-flex items-center gap-1"><Repeat class="size-3.5" aria-hidden="true" />{{ t.recurrence === 'daily' ? 'يومية' : 'أسبوعية' }}</span>
        <span v-if="t.kind !== 'personal' && t.size" class="num">{{ t.kind === 'house' ? count(t.size, POINTS) : `${t.size} س` }}</span>
      </p>
    </RouterLink>
    <span v-if="showAssignee && t.kind !== 'personal'" class="hidden items-center gap-2 text-[13.5px] sm:flex">
      <UAvatar :name="t.assigneeName || '؟'" :color="t.assigneeColor" size="sm" />
      {{ t.assigneeName || 'بلا مكلَّف' }}
    </span>
    <TaskStatus :task="t" class="hidden sm:inline-flex" />
    <RowActions :items="ta.items(t)" @action="ta.run(t, $event)" />
  </li>
</template>
