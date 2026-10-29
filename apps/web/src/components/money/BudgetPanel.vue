<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { CalendarPlus, Plus, Wallet } from 'lucide-vue-next';
import { DAY_NAMES, dayOfWeek, formatDate } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { INCOME_SOURCES, PERSONAL_CATEGORIES } from '../../lib/format.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import BudgetEntryForm from '../forms/BudgetEntryForm.vue';
import Money from '../ui/Money.vue';
import RowActions from '../ui/RowActions.vue';
import SectionCard from '../ui/SectionCard.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import USkeleton from '../ui/USkeleton.vue';
import WeekStartForm from '../forms/WeekStartForm.vue';

const ui = useUi();
const data = ref(null);
const history = ref([]);
const weekOpen = ref(false);
const entry = ref({ open: false, mode: 'expense', row: null });
const essential = ref({ open: false, row: null, title: '', amount: null, saving: false });

async function load() {
  try {
    data.value = await get('/budget');
    history.value = (await get('/budget/weeks')).weeks;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(() => [ui.versions.budget, ui.versions.money], load);

const s = computed(() => data.value?.summary);
const ranOut = computed(() => s.value && s.value.left < 0);

async function run(kind, row, key) {
  const base = kind === 'income' ? '/budget/incomes' : kind === 'essential' ? '/budget/essentials' : '/budget/expenses';
  try {
    if (key === 'edit') {
      if (kind === 'essential') essential.value = { open: true, row, title: row.title, amount: row.amount, saving: false };
      else entry.value = { open: true, mode: kind, row };
    } else if (key === 'copy') {
      data.value = await post(`${base}/${row.id}/copy`);
      ui.toast('نُسخ بتاريخ اليوم');
    } else if (key === 'delete') {
      if (await ui.confirm({ title: 'حذف هذا البند؟', confirmLabel: 'حذف', danger: true })) {
        data.value = await del(`${base}/${row.id}`);
        ui.toast('حُذف');
        ui.bump('budget');
      }
    }
  } catch (e) {
    ui.error(e);
  }
}
async function saveEssential() {
  const e = essential.value;
  e.saving = true;
  try {
    const body = { title: e.title, amount: e.amount ?? 0 };
    data.value = e.row ? await patch(`/budget/essentials/${e.row.id}`, body) : await post('/budget/essentials', body);
    essential.value.open = false;
    ui.bump('budget');
  } catch (err) {
    ui.error(err);
  } finally {
    e.saving = false;
  }
}
</script>

<template>
  <USkeleton v-if="!data" :lines="5" />
  <div v-else-if="!data.week" class="section">
    <UEmpty :icon="Wallet" title="ابدأ أسبوعك المالي" body="أدخل دخلك والأساسيات (مثل حصة الصندوق والمواصلات)، فيُقسَم الباقي على 7 أيام ويظهر لك مسموح كل يوم.">
      <UButton :icon="CalendarPlus" @click="weekOpen = true">أسبوع جديد</UButton>
    </UEmpty>
    <WeekStartForm :open="weekOpen" :current="data" @close="weekOpen = false" @saved="load" />
  </div>
  <div v-else class="space-y-5">
    <div class="grid gap-5 lg:grid-cols-[1.2fr_1fr]">
      <SectionCard :title="`الأسبوع: ${formatDate(data.week.startDate)} – ${formatDate(data.week.endDate)}`">
        <template #action>
          <UButton size="sm" variant="ghost" :icon="CalendarPlus" @click="weekOpen = true">أسبوع جديد</UButton>
        </template>
        <!-- The weekly arithmetic, spelled out -->
        <p class="num flex flex-wrap items-baseline gap-x-2 gap-y-1 text-[15px]">
          <Money :amount="s.totalIncome" :unit="false" /> <span class="text-muted">−</span> <Money :amount="s.essentialsTotal" :unit="false" />
          <span class="text-muted">=</span> <strong><Money :amount="s.remaining" :unit="false" /></strong>
          <span class="text-muted">÷ الأيام الباقية</span>
        </p>
        <div class="mt-4 grid grid-cols-3 gap-2 text-center">
          <div class="rounded-[12px] bg-sage-soft p-3"><p class="text-[13px] text-muted">مسموح اليوم</p><p class="text-[22px] font-bold text-forest"><Money :amount="s.allowedToday" :unit="false" /></p></div>
          <div class="rounded-[12px] bg-sunken p-3"><p class="text-[13px] text-muted">صرفت اليوم</p><p class="text-[22px] font-bold"><Money :amount="s.spentToday" :unit="false" /></p></div>
          <div class="rounded-[12px] p-3" :class="s.overToday ? 'bg-danger-soft' : 'bg-sunken'">
            <p class="text-[13px] text-muted">{{ s.overToday ? 'تجاوزت' : 'المتبقي اليوم' }}</p>
            <p class="text-[22px] font-bold" :class="s.overToday && 'text-danger'"><Money :amount="s.overToday || s.leftToday" :unit="false" /></p>
          </div>
        </div>
        <p v-if="ranOut" class="mt-3 rounded-[10px] bg-danger-soft px-3 py-2 text-[13.5px] text-danger">صرفت أكثر من ميزانية الأسبوع بـ <Money :amount="-s.left" />. أضف دخلاً أو خفّف حتى نهاية الأسبوع.</p>
        <div class="mt-4 flex gap-2">
          <UButton :icon="Plus" class="flex-1" @click="entry = { open: true, mode: 'expense', row: null }">مصروف</UButton>
          <UButton variant="secondary" :icon="Plus" class="flex-1" @click="entry = { open: true, mode: 'income', row: null }">دخل إضافي</UButton>
        </div>
      </SectionCard>

      <SectionCard title="أيام الأسبوع">
        <ul class="space-y-1.5">
          <li v-for="d in s.days" :key="d.date" class="flex items-center gap-3 rounded-[10px] px-2 py-1.5" :class="d.date === data.today && 'bg-brass-soft'">
            <span class="w-20 shrink-0 text-[14px]" :class="d.date === data.today && 'font-semibold'">{{ DAY_NAMES[dayOfWeek(d.date)] }}</span>
            <span class="h-2 flex-1 overflow-hidden rounded-full bg-sunken">
              <span v-if="d.allowed" class="block h-full rounded-full" :class="d.spent > d.allowed ? 'bg-danger' : 'bg-sage'" :style="{ width: `${Math.min(100, (d.spent / d.allowed) * 100)}%` }" />
              <span v-else-if="d.past && d.spent" class="block h-full w-full rounded-full bg-line" />
            </span>
            <span class="num w-36 shrink-0 text-end text-[13px]">
              <template v-if="d.past"><span class="text-muted">صرفت</span> <Money :amount="d.spent" :unit="false" /></template>
              <template v-else><Money :amount="d.spent" :unit="false" /> <span class="text-muted">/</span> <Money :amount="d.allowed" :unit="false" /></template>
            </span>
          </li>
        </ul>
        <p class="mt-3 text-[13px] text-muted">التوفير أو التجاوز في يوم يُوزَّع تلقائياً على الأيام الباقية.</p>
      </SectionCard>
    </div>

    <div class="grid gap-5 lg:grid-cols-3">
      <SectionCard title="المصروفات" flush class="lg:col-span-2">
        <ul v-if="data.expenses.length" class="divide-y divide-line px-2 pb-1">
          <li v-for="e in data.expenses" :key="e.id" class="flex items-center gap-3 px-2 py-2.5">
            <div class="min-w-0 flex-1">
              <p class="font-medium">{{ PERSONAL_CATEGORIES[e.category] }}<span v-if="e.note" class="font-normal text-muted"> · {{ e.note }}</span></p>
              <p class="text-[13px] text-muted">{{ formatDate(e.date, { weekday: true }) }}</p>
            </div>
            <Money :amount="e.amount" :unit="false" class="font-semibold" />
            <RowActions :items="actions(['edit', 'copy', 'delete'])" @action="run('expense', e, $event)" />
          </li>
        </ul>
        <p v-else class="px-4 pb-4 text-[14px] text-muted">لا مصروفات بعد هذا الأسبوع.</p>
      </SectionCard>
      <div class="space-y-5">
        <SectionCard title="الدخل" flush>
          <ul class="divide-y divide-line px-2 pb-1">
            <li v-for="i in data.incomes" :key="i.id" class="flex items-center gap-2 px-2 py-2.5">
              <span class="flex-1">{{ INCOME_SOURCES[i.source] || 'دخل' }}</span>
              <Money :amount="i.amount" :unit="false" class="font-semibold" />
              <RowActions :items="actions(['edit', 'copy', 'delete'])" @action="run('income', i, $event)" />
            </li>
            <li v-if="data.week.carriedIn" class="flex items-center justify-between px-2 py-2.5 text-muted"><span>مُرحَّل من الأسبوع الماضي</span><Money :amount="data.week.carriedIn" :unit="false" /></li>
          </ul>
        </SectionCard>
        <SectionCard title="الأساسيات" flush>
          <template #action><UButton size="sm" variant="ghost" :icon="Plus" @click="essential = { open: true, row: null, title: '', amount: null, saving: false }">بند</UButton></template>
          <ul class="divide-y divide-line px-2 pb-1">
            <li v-for="e in data.essentials" :key="e.id" class="flex items-center gap-2 px-2 py-2.5">
              <span class="flex-1">{{ e.title }}</span>
              <Money :amount="e.amount" :unit="false" class="font-semibold" />
              <RowActions :items="actions(['edit', 'delete'])" @action="run('essential', e, $event)" />
            </li>
            <li v-if="!data.essentials.length" class="px-2 py-2.5 text-[14px] text-muted">لا أساسيات</li>
          </ul>
        </SectionCard>
      </div>
    </div>

    <SectionCard v-if="history.length" title="الأسابيع السابقة" flush>
      <ul class="divide-y divide-line px-2 pb-1">
        <li v-for="w in history" :key="w.id" class="flex flex-wrap items-center gap-x-4 gap-y-1 px-2 py-2.5 text-[14px]">
          <span class="w-40 font-medium">{{ formatDate(w.startDate) }} – {{ formatDate(w.endDate) }}</span>
          <span class="text-muted">الدخل <Money :amount="w.summary?.income || 0" :unit="false" /></span>
          <span class="text-muted">المصروف <Money :amount="(w.summary?.spent || 0) + (w.summary?.essentials || 0)" :unit="false" /></span>
          <span v-if="w.savedAmount" class="text-sage">ادّخرت <Money :amount="w.savedAmount" :unit="false" /></span>
        </li>
      </ul>
    </SectionCard>

    <WeekStartForm :open="weekOpen" :current="data" @close="weekOpen = false" @saved="load" />
    <BudgetEntryForm :open="entry.open" :mode="entry.mode" :entry="entry.row" @close="entry.open = false" @saved="load" />
    <UDialog :open="essential.open" :title="essential.row ? 'تعديل بند أساسي' : 'بند أساسي'" @close="essential.open = false">
      <form id="essential-form" class="space-y-4" @submit.prevent="saveEssential">
        <UField v-slot="{ id }" label="البند"><input :id="id" v-model="essential.title" class="input" maxlength="60" required /></UField>
        <UField v-slot="{ id }" label="المبلغ"><AmountInput :id="id" v-model="essential.amount" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="essential-form" :loading="essential.saving" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="essential.open = false">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
