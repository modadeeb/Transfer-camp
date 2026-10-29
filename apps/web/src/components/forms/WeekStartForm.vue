<script setup>
import { computed, ref, watch } from 'vue';
import { Plus, X } from 'lucide-vue-next';
import { addDays, adenDate, formatDate, formatMoney } from '@camp/domain';
import { post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';

// current: the open week view from GET /budget (or null)
const props = defineProps({ open: Boolean, current: { type: Object, default: null } });
const emit = defineEmits(['close', 'saved']);
const ui = useUi();
const step = ref(1);
const { form, errors, saving, submit, reset } = useForm({ income: null, source: 'salary', leftover: 'carry', essentials: [] });
const hasCurrent = computed(() => Boolean(props.current?.week));
const leftover = computed(() => Math.max(0, props.current?.summary?.left ?? 0));
const firstStep = computed(() => (hasCurrent.value ? 1 : 2));
const total = computed(() => (form.income || 0) + (form.leftover === 'carry' ? leftover.value : 0) - form.essentials.reduce((s, e) => s + (e.amount || 0), 0));

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    const prev = (props.current?.essentials || []).map((e) => ({ title: e.title, amount: e.amount }));
    const fund = props.current?.fundShareDue || 0;
    if (fund && !prev.some((e) => e.title === 'حصة الصندوق المشترك')) prev.unshift({ title: 'حصة الصندوق المشترك', amount: fund });
    reset({ income: null, source: 'salary', leftover: 'carry', essentials: prev });
    step.value = firstStep.value;
  },
  { immediate: true },
);

async function save() {
  const r = await submit(() =>
    post('/budget/weeks', {
      income: form.income || 0,
      source: form.source,
      leftover: form.leftover,
      essentials: form.essentials.filter((e) => e.title && e.amount != null),
    }),
  );
  if (!r) return;
  ui.toast(`بدأ أسبوع جديد · مسموحك اليوم ${formatMoney(r.summary.allowedToday)}`);
  ui.bump('budget');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" title="أسبوع جديد" @close="emit('close')">
    <p class="mb-4 text-[13.5px] text-muted">يبدأ اليوم {{ formatDate(adenDate()) }} وينتهي {{ formatDate(addDays(adenDate(), 6), { weekday: true }) }}.</p>

    <div v-if="step === 1" class="space-y-4">
      <div class="rounded-[12px] bg-sunken p-4">
        <p class="font-semibold">ملخص الأسبوع الحالي</p>
        <dl class="mt-2 grid grid-cols-3 gap-2 text-[14px]">
          <div><dt class="text-muted">الدخل</dt><dd class="num font-medium">{{ formatMoney(current.summary.totalIncome) }}</dd></div>
          <div><dt class="text-muted">المصروف</dt><dd class="num font-medium">{{ formatMoney(current.summary.spentTotal + current.summary.essentialsTotal) }}</dd></div>
          <div><dt class="text-muted">المتبقي</dt><dd class="num font-medium">{{ formatMoney(leftover) }}</dd></div>
        </dl>
      </div>
      <UField v-if="leftover > 0" label="ماذا تفعل بالمتبقي؟">
        <USegment
          v-model="form.leftover"
          :options="[
            { value: 'carry', label: 'أضِفه للأسبوع الجديد' },
            { value: 'save', label: 'احتفظ به كمدّخر' },
          ]"
          label="المتبقي"
        />
      </UField>
    </div>

    <div v-else-if="step === 2" class="space-y-4">
      <UField v-slot="{ id, invalid, describedBy }" label="دخل هذا الأسبوع" :error="errors.income">
        <AmountInput :id="id" v-model="form.income" big :invalid="invalid" :described-by="describedBy" />
      </UField>
      <UField label="المصدر">
        <USegment
          v-model="form.source"
          :options="[
            { value: 'salary', label: 'راتب' },
            { value: 'freelance', label: 'عمل حر' },
            { value: 'family', label: 'من الأهل' },
            { value: 'other', label: 'أخرى' },
          ]"
          label="المصدر"
        />
      </UField>
    </div>

    <div v-else class="space-y-3">
      <p class="font-medium">الأساسيات التي تُصرف بداية الأسبوع</p>
      <div v-for="(e, i) in form.essentials" :key="i" class="flex items-center gap-2">
        <input v-model="e.title" class="input flex-1" placeholder="البند" :aria-label="`البند ${i + 1}`" />
        <div class="w-40"><AmountInput v-model="e.amount" /></div>
        <button type="button" class="grid size-9 shrink-0 place-items-center rounded-full text-muted hover:text-danger" :aria-label="`حذف البند ${i + 1}`" @click="form.essentials.splice(i, 1)">
          <X class="size-4" />
        </button>
      </div>
      <UButton variant="soft" size="sm" :icon="Plus" @click="form.essentials.push({ title: '', amount: null })">إضافة بند</UButton>
      <p v-if="errors.essentials" class="text-[13px] text-danger">{{ errors.essentials }}</p>
      <div class="rounded-[12px] bg-sage-soft p-4 text-[14.5px]">
        المتبقي للأسبوع <strong class="num">{{ formatMoney(total) }}</strong>
        ← مسموح اليوم <strong class="num">{{ formatMoney(Math.floor(total / 7)) }}</strong>
      </div>
    </div>

    <template #footer>
      <UButton v-if="step < 3" class="flex-1" @click="step++">التالي</UButton>
      <UButton v-else :loading="saving" class="flex-1" @click="save">بدء الأسبوع</UButton>
      <UButton v-if="step > firstStep" variant="secondary" @click="step--">رجوع</UButton>
      <UButton v-else variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
