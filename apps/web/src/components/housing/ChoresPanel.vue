<script setup>
import { onMounted, ref, watch } from 'vue';
import { Plus, Power, Sparkles } from 'lucide-vue-next';
import { DAY_NAMES, SLOT_LABELS } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { POINTS, count } from '../../lib/format.js';
import { choreIcon } from '../../lib/icons.js';
import { useReorder } from '../../lib/useReorder.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import ReorderArrows from '../ui/ReorderArrows.vue';
import RowActions from '../ui/RowActions.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import USkeleton from '../ui/USkeleton.vue';
import ChoreForm from './ChoreForm.vue';

const session = useSession();
const ui = useUi();
const chores = ref(null);
const archived = ref(false);
const editing = ref(null);
const formOpen = ref(false);
const viewing = ref(null);

async function load() {
  try {
    chores.value = (await get('/chores', { archived: archived.value ? 1 : undefined })).chores;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(archived, load);
watch(() => ui.versions.housing, load);
const reorder = useReorder('chores', chores, load);

const frequencyText = (c) =>
  c.frequency === 'daily' ? 'يومياً' : c.frequency === 'weekly' ? `كل ${DAY_NAMES[c.weeklyDay ?? 6]}` : c.days.map((d) => DAY_NAMES[d]).join('، ');

function itemsFor(c) {
  if (!session.isManager) return actions(['view']);
  return actions(['view', 'edit', 'copy', archived.value ? 'unarchive' : 'archive', 'delete'], [{ key: 'toggle', label: c.active ? 'إيقاف' : 'تفعيل', icon: Power }]);
}

async function run(c, key) {
  try {
    if (key === 'view') viewing.value = c;
    else if (key === 'edit') {
      editing.value = c;
      formOpen.value = true;
    } else if (key === 'copy') {
      await post(`/chores/${c.id}/copy`);
      ui.toast('نُسخت المهمة المنزلية');
      load();
    } else if (key === 'archive' || key === 'unarchive') {
      await post(`/chores/${c.id}/${key}`);
      ui.toast(key === 'archive' ? 'أُرشفت · لن تدخل في التوزيع' : 'أُعيدت من الأرشيف');
      load();
    } else if (key === 'toggle') {
      await patch(`/chores/${c.id}`, { active: !c.active });
      ui.toast(c.active ? 'أُوقفت · لن تدخل في التوزيع القادم' : 'فُعّلت');
      load();
    } else if (key === 'delete') {
      const ok = await ui.confirm({ title: `حذف «${c.name}»؟`, body: 'المهام المنشورة سابقاً تبقى كما هي. يمكن الاستعادة خلال 30 يوماً.', confirmLabel: 'حذف', danger: true });
      if (ok) await ui.deleteWithUndo({ remove: () => del(`/chores/${c.id}`), restore: () => post(`/chores/${c.id}/restore`), message: 'حُذفت المهمة المنزلية', after: load });
    }
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="max-w-xl text-[14px] text-muted">قائمة أعمال البيت التي يوزّعها النظام كل أسبوع. النقاط تقيس الجهد، والتوزيع يساوي مجموعها بين الجميع.</p>
      <div class="flex gap-2">
        <UButton variant="ghost" size="sm" :aria-pressed="archived" @click="archived = !archived">{{ archived ? 'الحالية' : 'الأرشيف' }}</UButton>
        <UButton v-if="session.isManager" :icon="Plus" @click="(editing = null), (formOpen = true)">مهمة سكن</UButton>
      </div>
    </div>
    <USkeleton v-if="!chores" />
    <section v-else-if="chores.length" class="section">
      <ul class="divide-y divide-line px-2 py-1 lg:px-3">
        <li v-for="(c, i) in chores" :key="c.id" class="flex items-center gap-3 px-2 py-3" :class="!c.active && 'opacity-60'">
          <ReorderArrows v-if="session.isManager && !archived" :first="i === 0" :last="i === chores.length - 1" @up="reorder.up(i)" @down="reorder.down(i)" />
          <span class="grid size-10 shrink-0 place-items-center rounded-[10px] bg-sage-soft text-forest"><component :is="choreIcon(c.icon)" class="size-5" /></span>
          <div class="min-w-0 flex-1">
            <p class="font-medium">{{ c.name }} <UBadge v-if="!c.active">موقوفة</UBadge></p>
            <p class="text-[13px] text-muted">{{ frequencyText(c) }} · {{ SLOT_LABELS[c.slot] }}<template v-if="c.peopleCount > 1">&nbsp;· <span class="num">{{ c.peopleCount }}</span> أفراد</template></p>
          </div>
          <span class="num chip bg-brass-soft text-[color:var(--brass)]">{{ count(c.points, POINTS) }}</span>
          <RowActions :items="itemsFor(c)" @action="run(c, $event)" />
        </li>
      </ul>
    </section>
    <UEmpty v-else :icon="Sparkles" :title="archived ? 'لا شيء في الأرشيف' : 'لا توجد مهام سكن بعد'" :body="session.isManager && !archived ? 'أضف أعمال البيت (الطبخ، الأطباق، القمامة…) ليوزّعها النظام بالتساوي.' : ''">
      <UButton v-if="session.isManager && !archived" :icon="Plus" @click="(editing = null), (formOpen = true)">أضف أول مهمة</UButton>
    </UEmpty>

    <ChoreForm :open="formOpen" :chore="editing" @close="formOpen = false" />
    <UDialog :open="Boolean(viewing)" :title="viewing?.name || ''" @close="viewing = null">
      <dl v-if="viewing" class="grid grid-cols-2 gap-3 pb-2 text-[14.5px]">
        <div><dt class="text-muted">التكرار</dt><dd>{{ frequencyText(viewing) }}</dd></div>
        <div><dt class="text-muted">الوقت</dt><dd>{{ SLOT_LABELS[viewing.slot] }}</dd></div>
        <div><dt class="text-muted">نقاط الجهد</dt><dd class="num">{{ viewing.points }}</dd></div>
        <div><dt class="text-muted">عدد الأفراد</dt><dd class="num">{{ viewing.peopleCount }}</dd></div>
        <div><dt class="text-muted">الحالة</dt><dd>{{ viewing.active ? 'فعّالة' : 'موقوفة' }}</dd></div>
      </dl>
    </UDialog>
  </div>
</template>
