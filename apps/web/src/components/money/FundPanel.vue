<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { BellRing, HandCoins, Pencil, Plus, Trash2 } from 'lucide-vue-next';
import { formatDate } from '@camp/domain';
import { del, get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import AmountInput from '../ui/AmountInput.vue';
import Money from '../ui/Money.vue';
import RowActions from '../ui/RowActions.vue';
import SectionCard from '../ui/SectionCard.vue';
import UAvatar from '../ui/UAvatar.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import USkeleton from '../ui/USkeleton.vue';
import MemberPicker from '../ui/MemberPicker.vue';

const session = useSession();
const ui = useUi();
const data = ref(null);
const dialog = ref(null); // 'period' | 'pay' | 'amount' | 'settle'
const target = ref(null);
const period = useForm({ title: '', amountPerMember: null, dueDate: '' });
const pay = useForm({ amount: null, date: '', note: '' });
const settle = useForm({ toUserId: null, amount: null, note: '' });

async function load() {
  try {
    data.value = await get('/fund');
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(() => ui.versions.money, load);

const STATUS = { paid: ['مدفوع', 'sage'], partial: ['جزئي', 'brass'], due: ['مستحق', 'neutral'], overdue: ['متأخر', 'danger'] };
const latest = computed(() => data.value?.periods?.[0] || null);

function open(kind, t = null) {
  target.value = t;
  dialog.value = kind;
  if (kind === 'period') period.reset({ title: '', amountPerMember: latest.value?.amountPerMember ?? null, dueDate: '' });
  if (kind === 'pay') pay.reset({ amount: t.remaining, date: '', note: '' });
  if (kind === 'amount') pay.reset({ amount: t.amountDue, date: '', note: '' });
  if (kind === 'settle') settle.reset({ toUserId: t?.toId ?? null, amount: t?.amount ?? null, note: '' });
}

async function savePeriod() {
  const r = await period.submit(() => post('/contribution-periods', { title: period.form.title, amountPerMember: period.form.amountPerMember, dueDate: period.form.dueDate || null }));
  if (!r) return;
  data.value = r;
  dialog.value = null;
  ui.toast('أُضيفت دورة المساهمات ووصل الإشعار للجميع');
}
async function savePay() {
  const r = await pay.submit(() =>
    dialog.value === 'amount' ? patch(`/contributions/${target.value.id}`, { amountDue: pay.form.amount }) : post(`/contributions/${target.value.id}/payments`, { amount: pay.form.amount, note: pay.form.note || null }),
  );
  if (!r) return;
  data.value = r;
  dialog.value = null;
  ui.toast('حُفظ');
  ui.bump('budget');
}
async function saveSettle() {
  const r = await settle.submit(() => post('/settlements', { toUserId: settle.form.toUserId, amount: settle.form.amount, note: settle.form.note || null }));
  if (!r) return;
  data.value = r;
  dialog.value = null;
  ui.toast('سُجّلت التسوية');
}
async function contributionAction(c, key) {
  try {
    if (key === 'pay') open('pay', c);
    if (key === 'amount') open('amount', c);
    if (key === 'remind') {
      await post(`/contributions/${c.id}/remind`);
      ui.toast(`وصل التذكير إلى ${c.userName}`);
    }
  } catch (e) {
    ui.error(e);
  }
}
async function deletePeriod(p) {
  if (!(await ui.confirm({ title: `حذف دورة «${p.title}»؟`, body: 'تُحذف معها المساهمات والدفعات المسجلة فيها.', confirmLabel: 'حذف', danger: true }))) return;
  await ui.deleteWithUndo({ remove: () => del(`/contribution-periods/${p.id}`), restore: () => post(`/contribution-periods/${p.id}/restore`), message: 'حُذفت الدورة', after: load });
}
const contributionItems = (c) =>
  session.isManager
    ? [
        ...(c.remaining > 0 ? [{ key: 'pay', label: 'تسجيل دفعة', icon: HandCoins, primary: true }] : []),
        { key: 'amount', label: 'تعديل الحصة', icon: Pencil },
        ...(c.remaining > 0 ? [{ key: 'remind', label: 'تذكير العضو', icon: BellRing }] : []),
      ]
    : [];
</script>

<template>
  <USkeleton v-if="!data" :lines="5" />
  <div v-else class="grid gap-5 lg:grid-cols-[1fr_1.4fr]">
    <div class="space-y-5">
      <SectionCard title="رصيد الصندوق">
        <p class="text-[32px] font-bold leading-none"><Money :amount="data.fund.balance" /></p>
        <dl class="mt-4 grid grid-cols-2 gap-3 text-[14px]">
          <div class="rounded-[10px] bg-sunken p-3"><dt class="text-muted">دخل من المساهمات</dt><dd class="font-semibold"><Money :amount="data.fund.inflow" /></dd></div>
          <div class="rounded-[10px] bg-sunken p-3"><dt class="text-muted">صُرف من الصندوق</dt><dd class="font-semibold"><Money :amount="data.fund.outflow" /></dd></div>
        </dl>
      </SectionCard>

      <SectionCard title="وضعي مع المجموعة" subtitle="من المصروفات المشتركة والديون والتسويات">
        <p class="text-[24px] font-bold" :class="data.me.net < 0 ? 'text-danger' : data.me.net > 0 ? 'text-sage' : ''">
          <Money :amount="Math.abs(data.me.net)" />
          <span class="block text-[14px] font-normal text-muted">{{ data.me.net > 0 ? 'لك عند المجموعة' : data.me.net < 0 ? 'عليك للمجموعة' : 'حسابك متوازن' }}</span>
        </p>
        <ul v-if="data.me.iOwe.length || data.me.owedToMe.length" class="mt-3 space-y-2 text-[14.5px]">
          <li v-for="t in data.me.iOwe" :key="`o${t.toId}`" class="flex items-center gap-2">
            <span class="flex-1">ادفع لـ <strong>{{ t.name }}</strong> <Money :amount="t.amount" /></span>
            <UButton size="sm" variant="soft" @click="open('settle', t)">سجّل أنك دفعت</UButton>
          </li>
          <li v-for="t in data.me.owedToMe" :key="`i${t.fromId}`">لك عند <strong>{{ t.name }}</strong> <Money :amount="t.amount" /></li>
        </ul>
      </SectionCard>

      <SectionCard title="أرصدة الأعضاء">
        <template #action><UButton size="sm" variant="ghost" @click="open('settle')">تسوية</UButton></template>
        <ul class="space-y-2">
          <li v-for="m in data.members.filter((x) => !x.archived)" :key="m.id" class="flex items-center gap-3">
            <UAvatar :name="m.name" :color="m.color" size="sm" />
            <span class="flex-1">{{ m.name }}</span>
            <span class="font-medium" :class="m.net < 0 ? 'text-danger' : m.net > 0 ? 'text-sage' : 'text-muted'"><Money :amount="m.net" signed /></span>
          </li>
        </ul>
        <div v-if="data.plan.length" class="mt-4 rounded-[12px] bg-sunken p-3">
          <p class="mb-2 text-[13.5px] font-medium">أقل عدد تحويلات لتصفية الحسابات</p>
          <ul class="space-y-1 text-[14px]">
            <li v-for="(t, i) in data.plan" :key="i">{{ t.fromName }} ← {{ t.toName }}: <Money :amount="t.amount" /></li>
          </ul>
        </div>
      </SectionCard>
    </div>

    <SectionCard title="المساهمات" subtitle="حصة كل فرد في الصندوق">
      <template #action><UButton v-if="session.isManager" size="sm" :icon="Plus" @click="open('period')">دورة جديدة</UButton></template>
      <div v-if="data.periods.length" class="space-y-5">
        <div v-for="p in data.periods" :key="p.id">
          <div class="mb-2 flex flex-wrap items-baseline gap-x-3">
            <h3 class="font-semibold">{{ p.title }}</h3>
            <span class="text-[13px] text-muted"><Money :amount="p.totalPaid" /> من <Money :amount="p.totalDue" /><template v-if="p.dueDate">&nbsp;· الاستحقاق {{ formatDate(p.dueDate) }}</template></span>
            <button v-if="session.isManager" type="button" class="ms-auto grid size-8 place-items-center rounded-full text-muted hover:text-danger" :aria-label="`حذف دورة ${p.title}`" @click="deletePeriod(p)"><Trash2 class="size-4" /></button>
          </div>
          <ul class="divide-y divide-line rounded-[12px] border border-line">
            <li v-for="c in p.contributions" :key="c.id" class="flex items-center gap-3 px-3 py-2.5">
              <UAvatar :name="c.userName" :color="c.userColor" size="sm" />
              <span class="flex-1">{{ c.userName }}</span>
              <span class="text-[13.5px] text-muted"><Money :amount="c.paid" :unit="false" /> / <Money :amount="c.amountDue" :unit="false" /></span>
              <UBadge :tone="STATUS[c.status][1]">{{ STATUS[c.status][0] }}</UBadge>
              <RowActions v-if="session.isManager" :items="contributionItems(c)" @action="contributionAction(c, $event)" />
            </li>
          </ul>
        </div>
      </div>
      <UEmpty v-else :icon="HandCoins" title="لا توجد دورات مساهمة بعد" :body="session.isManager ? 'أنشئ دورة (مثلاً «نوفمبر») بحصة كل فرد، ثم سجّل الدفعات.' : 'سيظهر هنا ما عليك عندما يفتح المدير دورة مساهمات.'" />
    </SectionCard>

    <UDialog :open="dialog === 'period'" title="دورة مساهمات جديدة" @close="dialog = null">
      <form id="period-form" class="space-y-4" @submit.prevent="savePeriod">
        <UField v-slot="{ id, invalid }" label="الاسم" :error="period.errors.value.title"><input :id="id" v-model="period.form.title" class="input" placeholder="مثال: نوفمبر 2026" :aria-invalid="invalid || undefined" /></UField>
        <UField v-slot="{ id, invalid }" label="حصة كل فرد" :error="period.errors.value.amountPerMember"><AmountInput :id="id" v-model="period.form.amountPerMember" :invalid="invalid" /></UField>
        <UField v-slot="{ id }" label="آخر موعد للدفع" optional><input :id="id" v-model="period.form.dueDate" type="date" class="input" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="period-form" :loading="period.saving.value" class="flex-1">إنشاء وإشعار الجميع</UButton>
        <UButton variant="secondary" @click="dialog = null">إلغاء</UButton>
      </template>
    </UDialog>

    <UDialog :open="dialog === 'pay' || dialog === 'amount'" :title="dialog === 'amount' ? `حصة ${target?.userName}` : `دفعة من ${target?.userName}`" @close="dialog = null">
      <form id="pay-form" class="space-y-4" @submit.prevent="savePay">
        <UField v-slot="{ id, invalid }" :label="dialog === 'amount' ? 'الحصة المستحقة' : 'المبلغ المدفوع'" :error="pay.errors.value.amount || pay.errors.value.amountDue">
          <AmountInput :id="id" v-model="pay.form.amount" big :invalid="invalid" />
        </UField>
        <UField v-if="dialog === 'pay'" v-slot="{ id }" label="ملاحظة" optional><input :id="id" v-model="pay.form.note" class="input" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="pay-form" :loading="pay.saving.value" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="dialog = null">إلغاء</UButton>
      </template>
    </UDialog>

    <UDialog :open="dialog === 'settle'" title="تسجيل تسوية" @close="dialog = null">
      <form id="settle-form" class="space-y-4" @submit.prevent="saveSettle">
        <p class="text-[14px] text-muted">سجّل مبلغاً دفعته لزميل لتصفية الحساب بينكما.</p>
        <UField label="دفعت إلى" :error="settle.errors.value.toUserId"><MemberPicker v-model="settle.form.toUserId" :exclude="[session.user.id]" /></UField>
        <UField v-slot="{ id, invalid }" label="المبلغ" :error="settle.errors.value.amount"><AmountInput :id="id" v-model="settle.form.amount" :invalid="invalid" /></UField>
        <UField v-slot="{ id }" label="ملاحظة" optional><input :id="id" v-model="settle.form.note" class="input" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="settle-form" :loading="settle.saving.value" class="flex-1">تسجيل</UButton>
        <UButton variant="secondary" @click="dialog = null">إلغاء</UButton>
      </template>
    </UDialog>
  </div>
</template>
