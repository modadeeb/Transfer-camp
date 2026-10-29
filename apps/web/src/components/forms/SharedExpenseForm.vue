<script setup>
import { computed, watch } from 'vue';
import { adenDate } from '@camp/domain';
import { patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import MemberPicker from '../ui/MemberPicker.vue';
import Money from '../ui/Money.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';
import { EXPENSE_CATEGORIES } from '../../lib/format.js';


const props = defineProps({ open: Boolean, expense: { type: Object, default: null } });
const emit = defineEmits(['close', 'saved']);
const session = useSession();
const ui = useUi();
const blank = () => ({
  title: '',
  amount: null,
  category: 'groceries',
  date: adenDate(),
  payer: 'me',
  payerId: null,
  splitMemberIds: session.activeMembers.map((m) => m.id),
  note: '',
  attachmentUrl: '',
});
const { form, errors, saving, submit, reset } = useForm(blank());

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    const e = props.expense;
    if (e) {
      reset({
        ...blank(),
        title: e.title,
        amount: e.amount,
        category: e.category,
        date: e.date,
        payer: e.paidFromFund ? 'fund' : e.payerId === session.user.id ? 'me' : 'member',
        payerId: e.payerId,
        splitMemberIds: e.splitMemberIds,
        note: e.note || '',
        attachmentUrl: e.attachmentUrl || '',
      });
    } else reset(blank());
  },
  { immediate: true },
);

const payerOptions = computed(() =>
  session.isManager
    ? [
        { value: 'me', label: 'أنا' },
        { value: 'member', label: 'عضو آخر' },
        { value: 'fund', label: 'الصندوق' },
      ]
    : [{ value: 'me', label: 'أنا' }],
);
const share = computed(() => (form.amount && form.splitMemberIds.length ? Math.ceil(form.amount / form.splitMemberIds.length) : 0));

async function save() {
  const body = {
    title: form.title,
    amount: form.amount,
    category: form.category,
    date: form.date,
    paidFromFund: form.payer === 'fund',
    payerId: form.payer === 'fund' ? null : form.payer === 'me' ? session.user.id : form.payerId,
    splitMemberIds: form.splitMemberIds,
    note: form.note || null,
    attachmentUrl: form.attachmentUrl || null,
  };
  const r = await submit(() => (props.expense ? patch(`/shared-expenses/${props.expense.id}`, body) : post('/shared-expenses', body)));
  if (!r) return;
  ui.toast(props.expense ? 'حُفظ المصروف' : 'سُجّل المصروف المشترك');
  ui.bump('money');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" :title="expense ? 'تعديل مصروف مشترك' : 'مصروف مشترك'" @close="emit('close')">
    <form id="shared-expense-form" class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id, invalid, describedBy }" label="المبلغ" :error="errors.amount">
        <AmountInput :id="id" v-model="form.amount" big :invalid="invalid" :described-by="describedBy" />
      </UField>
      <UField v-slot="{ id, invalid }" label="البند" :error="errors.title">
        <input :id="id" v-model="form.title" class="input" maxlength="100" placeholder="مثال: خضار وفواكه" :aria-invalid="invalid || undefined" />
      </UField>
      <UField label="التصنيف">
        <USegment v-model="form.category" :options="Object.entries(EXPENSE_CATEGORIES).map(([value, label]) => ({ value, label }))" label="التصنيف" />
      </UField>
      <UField label="من دفع؟" :error="errors.payerId">
        <USegment v-model="form.payer" :options="payerOptions" label="من دفع" />
        <MemberPicker v-if="form.payer === 'member'" v-model="form.payerId" :exclude="[session.user.id]" class="mt-2" />
      </UField>
      <UField label="يُقسَّم على" :error="errors.splitMemberIds" :hint="share ? `حصة كل فرد تقريباً ${share.toLocaleString('en')} ر.ي` : ''">
        <MemberPicker v-model="form.splitMemberIds" multiple />
      </UField>
      <div class="grid grid-cols-2 gap-4">
        <UField v-slot="{ id }" label="التاريخ" :error="errors.date">
          <input :id="id" v-model="form.date" type="date" class="input" />
        </UField>
        <UField v-slot="{ id }" label="رابط الفاتورة" optional :error="errors.attachmentUrl">
          <input :id="id" v-model="form.attachmentUrl" class="input" dir="ltr" placeholder="https://" />
        </UField>
      </div>
      <UField v-slot="{ id }" label="ملاحظة" optional>
        <input :id="id" v-model="form.note" class="input" maxlength="500" />
      </UField>
      <p v-if="form.payer === 'fund'" class="rounded-[10px] bg-brass-soft px-3 py-2 text-[13.5px]">يُخصم من رصيد الصندوق ولا يغيّر حسابات الأفراد.</p>
      <p v-else-if="form.amount" class="rounded-[10px] bg-sage-soft px-3 py-2 text-[13.5px]">
        يُضاف لمن دفع <Money :amount="form.amount" /> ويُخصم من كل فرد حصته.
      </p>
    </form>
    <template #footer>
      <UButton type="submit" form="shared-expense-form" :loading="saving" class="flex-1">{{ expense ? 'حفظ' : 'تسجيل المصروف' }}</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
