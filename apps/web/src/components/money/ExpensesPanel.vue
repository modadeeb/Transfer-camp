<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { ExternalLink, Landmark, Plus, ShoppingBasket } from 'lucide-vue-next';
import { addDays, adenDate, formatDate } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, post } from '../../lib/api.js';
import { EXPENSE_CATEGORIES } from '../../lib/format.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import SharedExpenseForm from '../forms/SharedExpenseForm.vue';
import Money from '../ui/Money.vue';
import RowActions from '../ui/RowActions.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const expenses = ref(null);
const month = ref(adenDate().slice(0, 7));
const category = ref('');
const editing = ref(null);
const formOpen = ref(false);
const viewing = ref(null);

async function load() {
  const [y, m] = month.value.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  try {
    expenses.value = (await get('/shared-expenses', { from: `${month.value}-01`, to: `${month.value}-${last}`, category: category.value || undefined })).expenses;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch([month, category], load);
watch(() => ui.versions.money, load);

const total = computed(() => (expenses.value || []).reduce((s, e) => s + e.amount, 0));
const canEdit = (e) => session.isManager || e.createdBy === session.user.id;
const itemsFor = (e) => actions(canEdit(e) ? ['view', 'edit', 'copy', 'delete'] : ['view']);
async function run(e, key) {
  try {
    if (key === 'view') viewing.value = e;
    else if (key === 'edit') {
      editing.value = e;
      formOpen.value = true;
    } else if (key === 'copy') {
      await post(`/shared-expenses/${e.id}/copy`);
      ui.toast('نُسخ المصروف بتاريخ اليوم');
      ui.bump('money');
    } else if (key === 'delete') {
      if (await ui.confirm({ title: `حذف «${e.title}»؟`, body: 'تُعاد حسابات الأعضاء تلقائياً.', confirmLabel: 'حذف', danger: true })) {
        await ui.deleteWithUndo({ remove: () => del(`/shared-expenses/${e.id}`), restore: () => post(`/shared-expenses/${e.id}/restore`), message: 'حُذف المصروف', after: () => ui.bump('money') });
      }
    }
  } catch (err) {
    ui.error(err);
  }
}
const prevMonth = () => (month.value = addDays(`${month.value}-01`, -1).slice(0, 7));
const nextMonth = () => (month.value = addDays(`${month.value}-28`, 7).slice(0, 7));
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center gap-2">
      <UButton variant="ghost" size="sm" @click="prevMonth">الشهر السابق</UButton>
      <input v-model="month" type="month" class="input w-auto" aria-label="الشهر" />
      <UButton variant="ghost" size="sm" @click="nextMonth">التالي</UButton>
      <select v-model="category" class="input w-auto" aria-label="التصنيف">
        <option value="">كل التصنيفات</option>
        <option v-for="(label, key) in EXPENSE_CATEGORIES" :key="key" :value="key">{{ label }}</option>
      </select>
      <UButton :icon="Plus" class="ms-auto" @click="(editing = null), (formOpen = true)">مصروف مشترك</UButton>
    </div>
    <USkeleton v-if="!expenses" />
    <section v-else-if="expenses.length" class="section">
      <p class="border-b border-line px-4 py-3 text-[14px] text-muted">مجموع الشهر <strong class="text-ink"><Money :amount="total" /></strong></p>
      <ul class="divide-y divide-line px-2">
        <li v-for="e in expenses" :key="e.id" class="flex items-center gap-3 px-2 py-3">
          <span class="grid size-10 shrink-0 place-items-center rounded-[10px]" :class="e.paidFromFund ? 'bg-brass-soft text-[color:var(--brass)]' : 'bg-sage-soft text-forest'">
            <Landmark v-if="e.paidFromFund" class="size-5" /><ShoppingBasket v-else class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate font-medium">{{ e.title }}</p>
            <p class="text-[13px] text-muted">{{ EXPENSE_CATEGORIES[e.category] }} · {{ formatDate(e.date) }} · {{ e.paidFromFund ? 'من الصندوق' : `دفعه ${e.payerName}` }} · على {{ e.splitMemberIds.length }}</p>
          </div>
          <span class="font-semibold"><Money :amount="e.amount" :unit="false" /></span>
          <RowActions :items="itemsFor(e)" @action="run(e, $event)" />
        </li>
      </ul>
    </section>
    <UEmpty v-else :icon="ShoppingBasket" title="لا مصروفات مشتركة في هذا الشهر" body="سجّل ما تشتريه للبيت ليتقاسمه الجميع بعدل." />

    <SharedExpenseForm :open="formOpen" :expense="editing" @close="formOpen = false" />
    <UDialog :open="Boolean(viewing)" :title="viewing?.title || ''" @close="viewing = null">
      <div v-if="viewing" class="space-y-3 pb-2 text-[14.5px]">
        <p class="text-[24px] font-bold"><Money :amount="viewing.amount" /></p>
        <p class="text-muted">{{ EXPENSE_CATEGORIES[viewing.category] }} · {{ formatDate(viewing.date, { weekday: true }) }} · {{ viewing.paidFromFund ? 'من الصندوق' : `دفعه ${viewing.payerName}` }}</p>
        <p v-if="viewing.note">{{ viewing.note }}</p>
        <a v-if="viewing.attachmentUrl" :href="viewing.attachmentUrl" target="_blank" rel="noopener" class="inline-flex items-center gap-1 text-link underline"><ExternalLink class="size-4" />الفاتورة</a>
        <div>
          <p class="mb-1 font-medium">الحصص</p>
          <ul class="space-y-1">
            <li v-for="(share, id) in viewing.shares" :key="id" class="flex justify-between"><span>{{ session.memberName(Number(id)) }}</span><Money :amount="share" /></li>
          </ul>
        </div>
        <p class="text-[13px] text-muted">أضافه {{ viewing.createdByName }}</p>
      </div>
    </UDialog>
  </div>
</template>
