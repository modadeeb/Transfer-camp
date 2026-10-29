<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { HandCoins, Plus, Scale } from 'lucide-vue-next';
import { formatDate } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import MemberPicker from '../ui/MemberPicker.vue';
import Money from '../ui/Money.vue';
import RowActions from '../ui/RowActions.vue';
import UAvatar from '../ui/UAvatar.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import UProgress from '../ui/UProgress.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const debts = ref(null);
const view = ref('owe');
const archived = ref(false);
const dialog = ref(null);
const target = ref(null);
const payments = ref([]);
const debtForm = useForm({ otherUserId: null, direction: 'owe', amount: null, title: '', dueDate: '', note: '' });
const payForm = useForm({ amount: null, note: '' });

async function load() {
  try {
    debts.value = (await get('/debts', { archived: archived.value ? 1 : undefined })).debts;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(archived, load);
watch(() => ui.versions.money, load);

const me = computed(() => session.user.id);
const lists = computed(() => {
  const all = debts.value || [];
  return {
    owe: all.filter((d) => d.debtorId === me.value && d.remaining > 0),
    owed: all.filter((d) => d.creditorId === me.value && d.remaining > 0),
    settled: all.filter((d) => d.remaining === 0),
  };
});
const totals = computed(() => ({
  owe: lists.value.owe.reduce((s, d) => s + d.remaining, 0),
  owed: lists.value.owed.reduce((s, d) => s + d.remaining, 0),
}));
const other = (d) => (d.creditorId === me.value ? d.debtorName : d.creditorName);

function openDebt(d = null) {
  target.value = d;
  debtForm.reset(
    d
      ? { otherUserId: d.creditorId === me.value ? d.debtorId : d.creditorId, direction: d.creditorId === me.value ? 'owed' : 'owe', amount: d.amount, title: d.title || '', dueDate: d.dueDate || '', note: d.note || '' }
      : { otherUserId: null, direction: view.value === 'owed' ? 'owed' : 'owe', amount: null, title: '', dueDate: '', note: '' },
  );
  dialog.value = 'debt';
}
async function saveDebt() {
  const f = debtForm.form;
  const r = await debtForm.submit(() =>
    target.value
      ? patch(`/debts/${target.value.id}`, { amount: f.amount, title: f.title || null, dueDate: f.dueDate || null, note: f.note || null })
      : post('/debts', { otherUserId: f.otherUserId, direction: f.direction, amount: f.amount, title: f.title || null, dueDate: f.dueDate || null, note: f.note || null }),
  );
  if (!r) return;
  dialog.value = null;
  ui.toast(target.value ? 'حُفظ الدين' : 'سُجّل الدين');
  ui.bump('money');
}
async function savePay() {
  const r = await payForm.submit(() => post(`/debts/${target.value.id}/payments`, { amount: payForm.form.amount, note: payForm.form.note || null }));
  if (!r) return;
  dialog.value = null;
  ui.toast(r.debt.remaining === 0 ? 'سُدِّد الدين بالكامل ✓' : 'سُجّلت الدفعة');
  ui.bump('money');
}

const itemsFor = (d) => {
  const keys = ['view'];
  const mine = d.createdBy === me.value || session.isManager;
  if (mine) keys.push('edit', archived.value ? 'unarchive' : 'archive', 'delete');
  return actions(keys, d.remaining > 0 ? [{ key: 'pay', label: 'تسديد', icon: HandCoins, primary: true }] : []);
};
async function run(d, key) {
  try {
    if (key === 'view') {
      target.value = d;
      payments.value = (await get(`/debts/${d.id}/payments`)).payments;
      dialog.value = 'view';
    } else if (key === 'edit') openDebt(d);
    else if (key === 'pay') {
      target.value = d;
      payForm.reset({ amount: d.remaining, note: '' });
      dialog.value = 'pay';
    } else if (key === 'archive' || key === 'unarchive') {
      await post(`/debts/${d.id}/${key}`);
      ui.toast(key === 'archive' ? 'أُرشف الدين' : 'أُعيد من الأرشيف');
      load();
    } else if (key === 'delete') {
      if (await ui.confirm({ title: 'حذف الدين؟', body: 'يُحذف معه سجل الدفعات من الحسابات.', confirmLabel: 'حذف', danger: true })) {
        await ui.deleteWithUndo({ remove: () => del(`/debts/${d.id}`), restore: () => post(`/debts/${d.id}/restore`), message: 'حُذف الدين', after: () => ui.bump('money') });
      }
    }
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="grid grid-cols-2 gap-3">
      <div class="section p-4"><p class="text-[13px] text-muted">عليّ</p><p class="text-[22px] font-bold"><Money :amount="totals.owe" /></p></div>
      <div class="section p-4"><p class="text-[13px] text-muted">لي</p><p class="text-[22px] font-bold text-sage"><Money :amount="totals.owed" /></p></div>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <USegment
        v-model="view"
        :options="[
          { value: 'owe', label: `عليّ (${lists.owe.length})` },
          { value: 'owed', label: `لي (${lists.owed.length})` },
          { value: 'settled', label: 'مسدَّدة' },
        ]"
        label="الديون"
      />
      <div class="flex gap-2">
        <UButton variant="ghost" size="sm" :aria-pressed="archived" @click="archived = !archived">{{ archived ? 'الحالية' : 'الأرشيف' }}</UButton>
        <UButton :icon="Plus" @click="openDebt()">دين</UButton>
      </div>
    </div>
    <USkeleton v-if="!debts" :lines="3" />
    <section v-else-if="lists[view].length" class="section">
      <ul class="divide-y divide-line px-2">
        <li v-for="d in lists[view]" :key="d.id" class="flex items-center gap-3 px-2 py-3">
          <UAvatar :name="other(d)" size="md" :color="session.member(d.creditorId === me ? d.debtorId : d.creditorId)?.color" />
          <div class="min-w-0 flex-1 space-y-1.5">
            <p class="font-medium">{{ other(d) }}<span v-if="d.title" class="font-normal text-muted"> · {{ d.title }}</span></p>
            <div class="flex items-center gap-2">
              <UProgress :value="(d.paid / d.amount) * 100" :label="`المسدد من ${d.amount}`" class="max-w-40" />
              <span class="text-[12.5px] text-muted"><Money :amount="d.paid" :unit="false" /> / <Money :amount="d.amount" :unit="false" /></span>
            </div>
            <p v-if="d.dueDate" class="text-[12.5px] text-muted">الاستحقاق {{ formatDate(d.dueDate) }}</p>
          </div>
          <span class="text-end font-semibold"><Money :amount="d.remaining || d.amount" :unit="false" /></span>
          <RowActions :items="itemsFor(d)" @action="run(d, $event)" />
        </li>
      </ul>
    </section>
    <UEmpty v-else :icon="Scale" :title="view === 'settled' ? 'لا ديون مسدَّدة' : view === 'owe' ? 'لا ديون عليك' : 'لا ديون لك'" body="سجّل السلف بين أفراد المعسكر وسدّدها على دفعات." />

    <UDialog :open="dialog === 'debt'" :title="target ? 'تعديل الدين' : 'دين جديد'" @close="dialog = null">
      <form id="debt-form" class="space-y-4" @submit.prevent="saveDebt">
        <template v-if="!target">
          <UField label="الاتجاه">
            <USegment
              v-model="debtForm.form.direction"
              :options="[
                { value: 'owe', label: 'أنا مدين له' },
                { value: 'owed', label: 'هو مدين لي' },
              ]"
              label="الاتجاه"
            />
          </UField>
          <UField label="الزميل" :error="debtForm.errors.value.otherUserId"><MemberPicker v-model="debtForm.form.otherUserId" :exclude="[me]" /></UField>
        </template>
        <UField v-slot="{ id, invalid }" label="المبلغ" :error="debtForm.errors.value.amount"><AmountInput :id="id" v-model="debtForm.form.amount" big :invalid="invalid" /></UField>
        <div class="grid grid-cols-2 gap-4">
          <UField v-slot="{ id }" label="الوصف" optional><input :id="id" v-model="debtForm.form.title" class="input" maxlength="100" placeholder="سلفة، غداء…" /></UField>
          <UField v-slot="{ id }" label="الاستحقاق" optional><input :id="id" v-model="debtForm.form.dueDate" type="date" class="input" /></UField>
        </div>
        <UField v-slot="{ id }" label="ملاحظة" optional><input :id="id" v-model="debtForm.form.note" class="input" maxlength="500" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="debt-form" :loading="debtForm.saving.value" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="dialog = null">إلغاء</UButton>
      </template>
    </UDialog>

    <UDialog :open="dialog === 'pay'" :title="`تسديد ${target ? other(target) : ''}`" @close="dialog = null">
      <form id="debt-pay-form" class="space-y-4" @submit.prevent="savePay">
        <p v-if="target" class="text-[14px] text-muted">المتبقي <Money :amount="target.remaining" /> — دفعة جزئية أو كاملة.</p>
        <UField v-slot="{ id, invalid }" label="المبلغ" :error="payForm.errors.value.amount"><AmountInput :id="id" v-model="payForm.form.amount" big :invalid="invalid" /></UField>
        <UField v-slot="{ id }" label="ملاحظة" optional><input :id="id" v-model="payForm.form.note" class="input" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="debt-pay-form" :loading="payForm.saving.value" class="flex-1">تسجيل الدفعة</UButton>
        <UButton variant="secondary" @click="dialog = null">إلغاء</UButton>
      </template>
    </UDialog>

    <UDialog :open="dialog === 'view'" :title="target ? `دين ${other(target)}` : ''" @close="dialog = null">
      <div v-if="target" class="space-y-3 pb-2 text-[14.5px]">
        <p>{{ target.creditorId === me ? `${target.debtorName} مدين لك` : `أنت مدين لـ ${target.creditorName}` }} بـ <Money :amount="target.amount" /></p>
        <p v-if="target.note" class="text-muted">{{ target.note }}</p>
        <p class="font-medium">الدفعات</p>
        <ul v-if="payments.length" class="space-y-1">
          <li v-for="p in payments" :key="p.id" class="flex justify-between"><span>{{ formatDate(p.date) }}<span v-if="p.note" class="text-muted"> · {{ p.note }}</span></span><Money :amount="p.amount" /></li>
        </ul>
        <p v-else class="text-muted">لا دفعات بعد.</p>
      </div>
    </UDialog>
  </div>
</template>
