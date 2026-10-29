<script setup>
import { computed, ref, watch } from 'vue';
import { adenDate, formatMoney } from '@camp/domain';
import { get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';
import { INCOME_SOURCES, PERSONAL_CATEGORIES } from '../../lib/format.js';

const CATEGORIES = PERSONAL_CATEGORIES;
const SOURCES = INCOME_SOURCES;

// mode: 'expense' | 'income'
const props = defineProps({ open: Boolean, mode: { type: String, default: 'expense' }, entry: { type: Object, default: null } });
const emit = defineEmits(['close', 'saved', 'need-week']);
const ui = useUi();
const preview = ref(null);
const blank = () => ({ amount: null, category: 'food', source: 'salary', date: adenDate(), note: '' });
const { form, errors, saving, submit, reset } = useForm(blank());
const isExpense = computed(() => props.mode === 'expense');

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    preview.value = null;
    const e = props.entry;
    reset(e ? { ...blank(), amount: e.amount, category: e.category || 'food', source: e.source || 'other', date: e.date, note: e.note || '' } : blank());
  },
  { immediate: true },
);

let timer;
watch(
  () => [form.amount, form.date],
  () => {
    clearTimeout(timer);
    if (props.entry || !form.amount) {
      preview.value = null;
      return;
    }
    timer = setTimeout(async () => {
      try {
        preview.value = await get('/budget/preview', isExpense.value ? { expense: form.amount, date: form.date } : { income: form.amount });
      } catch {
        preview.value = null;
      }
    }, 250);
  },
);

async function save() {
  const base = isExpense.value ? '/budget/expenses' : '/budget/incomes';
  const body = { amount: form.amount, date: form.date, note: form.note || null, ...(isExpense.value ? { category: form.category } : { source: form.source }) };
  const r = await submit(() => (props.entry ? patch(`${base}/${props.entry.id}`, body) : post(base, body)));
  if (!r) return;
  const s = r.summary;
  if (isExpense.value && !props.entry && s.overToday > 0) ui.toast(`سُجّل المصروف · تجاوزت اليوم بـ ${formatMoney(s.overToday)}، ووُزّع الفرق على الأيام القادمة`);
  else if (!isExpense.value && !props.entry) ui.toast(`أُضيف الدخل · ارتفع مسموحك اليومي إلى ${formatMoney(s.allowedToday)}`);
  else ui.toast('حُفظ');
  ui.bump('budget');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" :title="entry ? (isExpense ? 'تعديل مصروف' : 'تعديل دخل') : isExpense ? 'مصروف شخصي' : 'دخل إضافي'" @close="emit('close')">
    <form id="budget-entry-form" class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id, invalid, describedBy }" label="المبلغ" :error="errors.amount">
        <AmountInput :id="id" v-model="form.amount" big :invalid="invalid" :described-by="describedBy" />
      </UField>
      <UField v-if="isExpense" label="التصنيف">
        <USegment v-model="form.category" :options="Object.entries(CATEGORIES).map(([value, label]) => ({ value, label }))" label="التصنيف" />
      </UField>
      <UField v-else label="المصدر">
        <USegment v-model="form.source" :options="Object.entries(SOURCES).map(([value, label]) => ({ value, label }))" label="المصدر" />
      </UField>
      <div class="grid grid-cols-2 gap-4">
        <UField v-slot="{ id }" label="التاريخ" :error="errors.date">
          <input :id="id" v-model="form.date" type="date" class="input" :max="adenDate()" />
        </UField>
        <UField v-slot="{ id }" label="ملاحظة" optional>
          <input :id="id" v-model="form.note" class="input" maxlength="200" />
        </UField>
      </div>
      <p v-if="preview && preview.allowedToday !== null" class="rounded-[10px] px-3 py-2 text-[13.5px]" :class="preview.overToday ? 'bg-brass-soft' : 'bg-sage-soft'">
        <template v-if="isExpense && preview.overToday">ستتجاوز اليوم بـ {{ formatMoney(preview.overToday) }}، ويُوزَّع الفرق على الأيام القادمة.</template>
        <template v-else-if="isExpense">يبقى لك اليوم {{ formatMoney(preview.leftToday) }}.</template>
        <template v-else>سيرتفع مسموحك اليومي إلى {{ formatMoney(preview.allowedToday) }}.</template>
      </p>
    </form>
    <template #footer>
      <UButton type="submit" form="budget-entry-form" :loading="saving" class="flex-1">{{ entry ? 'حفظ' : isExpense ? 'تسجيل المصروف' : 'إضافة الدخل' }}</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
