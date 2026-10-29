<script setup>
import { computed, ref } from 'vue';
import { CalendarClock, CalendarOff, Copy, KeyRound, Plus, ShieldCheck, UserPlus } from 'lucide-vue-next';
import { DAY_NAMES, SPECIALTIES, formatDate, formatTime } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, patch, post } from '../../lib/api.js';
import { SLOT_KINDS } from '../../lib/format.js';
import { useForm } from '../../lib/useForm.js';
import { useReorder } from '../../lib/useReorder.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import SlotsEditor from '../SlotsEditor.vue';
import ReorderArrows from '../ui/ReorderArrows.vue';
import RowActions from '../ui/RowActions.vue';
import UAvatar from '../ui/UAvatar.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';

const session = useSession();
const ui = useUi();
const COLORS = ['#243F35', '#56856A', '#B68A47', '#4F6D8A', '#8A5A6E', '#6E7F4F', '#A0644B', '#5B6B9A'];
const list = computed({ get: () => session.members, set: (v) => (session.members = v) });
const reorder = useReorder('members', list, () => session.loadMembers());
const formOpen = ref(false);
const editing = ref(null);
const viewing = ref(null);
const slotsFor = ref(null);
const credentials = ref(null);
const { form, errors, saving, submit, reset } = useForm({ name: '', username: '', role: 'member', specialty: null, phone: '', color: COLORS[1] });

function openForm(m = null) {
  editing.value = m;
  reset(m ? { name: m.name, username: m.username, role: m.role, specialty: m.specialty, phone: m.phone || '', color: m.color || COLORS[1] } : { name: '', username: '', role: 'member', specialty: null, phone: '', color: COLORS[session.members.length % COLORS.length] });
  formOpen.value = true;
}
async function save() {
  const body = { name: form.name, role: form.role, specialty: form.specialty || null, phone: form.phone || null, color: form.color };
  const r = await submit(() => (editing.value ? patch(`/members/${editing.value.id}`, body) : post('/members', { ...body, username: form.username.trim() })));
  if (!r) return;
  formOpen.value = false;
  await session.loadMembers();
  if (!editing.value) credentials.value = { name: r.member.name, username: r.member.username, password: r.tempPassword };
  else ui.toast('حُفظت بيانات العضو');
}
const itemsFor = (m) => {
  const self = m.id === session.user.id;
  const keys = ['view', 'edit'];
  if (!self) keys.push(m.archivedAt ? 'unarchive' : 'archive', 'delete');
  return actions(keys, [
    { key: 'slots', label: 'أوقات الجامعة والعمل', icon: CalendarClock },
    { key: 'absence', label: 'تسجيل غياب', icon: CalendarOff },
    ...(self ? [] : [{ key: 'reset', label: 'إعادة تعيين كلمة المرور', icon: KeyRound }]),
  ]);
};
async function run(m, key) {
  try {
    if (key === 'view') viewing.value = m;
    else if (key === 'edit') openForm(m);
    else if (key === 'slots') slotsFor.value = m;
    else if (key === 'absence') ui.quickAdd = 'absence';
    else if (key === 'reset') {
      if (!(await ui.confirm({ title: `إعادة تعيين كلمة مرور ${m.name}؟`, body: 'تُلغى جلساته الحالية ويحصل على كلمة مرور مؤقتة.', confirmLabel: 'إعادة التعيين' }))) return;
      const r = await post(`/members/${m.id}/reset-password`);
      credentials.value = { name: m.name, username: m.username, password: r.tempPassword };
    } else if (key === 'archive' || key === 'unarchive') {
      if (key === 'archive' && !(await ui.confirm({ title: `أرشفة ${m.name}؟`, body: 'لن يستطيع الدخول ولن يدخل في التوزيع. تبقى بياناته ومهامه السابقة.', confirmLabel: 'أرشفة' }))) return;
      await post(`/members/${m.id}/${key}`);
      ui.toast(key === 'archive' ? `أُرشف ${m.name}` : `أُعيد ${m.name}`);
      await session.loadMembers();
    } else if (key === 'delete') {
      if (!(await ui.confirm({ title: `حذف ${m.name}؟`, body: 'يُلغى دخوله فوراً. يمكن الاستعادة من المحذوفات خلال 30 يوماً.', confirmLabel: 'حذف', danger: true }))) return;
      await ui.deleteWithUndo({
        remove: () => del(`/members/${m.id}`),
        restore: () => post('/trash/restore', { entity: 'user', id: m.id }),
        message: `حُذف ${m.name}`,
        after: () => session.loadMembers(),
      });
    }
  } catch (e) {
    ui.error(e);
  }
}
async function copyCreds() {
  const c = credentials.value;
  const text = `${session.campName}\nاسم المستخدم: ${c.username}\nكلمة المرور المؤقتة: ${c.password}\n${location.origin}`;
  try {
    await navigator.clipboard.writeText(text);
    ui.toast('نُسخت بيانات الدخول');
  } catch {
    ui.toast('انسخها يدوياً', { type: 'error' });
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <p class="text-[14px] text-muted"><span class="num">{{ session.activeMembers.length }}</span> أعضاء نشطين. الترتيب هنا هو ترتيب الأسماء في كل القوائم.</p>
      <UButton :icon="UserPlus" @click="openForm()">عضو</UButton>
    </div>
    <section class="section">
      <ul class="divide-y divide-line px-2">
        <li v-for="(m, i) in session.members" :key="m.id" class="flex items-center gap-3 px-2 py-3" :class="m.archivedAt && 'opacity-60'">
          <ReorderArrows :first="i === 0" :last="i === session.members.length - 1" @up="reorder.up(i)" @down="reorder.down(i)" />
          <UAvatar :name="m.name" :color="m.color" />
          <div class="min-w-0 flex-1">
            <p class="font-medium">
              {{ m.name }}
              <UBadge v-if="m.role === 'manager'" tone="solid"><ShieldCheck class="size-3" />مدير</UBadge>
              <UBadge v-if="m.archivedAt">مؤرشف</UBadge>
            </p>
            <p class="text-[13px] text-muted" dir="auto">{{ m.specialty ? SPECIALTIES[m.specialty] : 'بلا تخصص' }} · <span dir="ltr">{{ m.username }}</span><template v-if="m.slots.length">&nbsp;· {{ m.slots.length }} أوقات ثابتة</template></p>
          </div>
          <RowActions :items="itemsFor(m)" @action="run(m, $event)" />
        </li>
      </ul>
    </section>

    <UDialog :open="formOpen" :title="editing ? `تعديل ${editing.name}` : 'عضو جديد'" @close="formOpen = false">
      <form id="member-form" class="space-y-4" @submit.prevent="save">
        <UField v-slot="{ id, invalid }" label="الاسم" :error="errors.name"><input :id="id" v-model="form.name" class="input" maxlength="60" :aria-invalid="invalid || undefined" /></UField>
        <UField v-if="!editing" v-slot="{ id, invalid }" label="اسم المستخدم" hint="بالأحرف الإنجليزية، يُستخدم للدخول" :error="errors.username">
          <input :id="id" v-model="form.username" class="input" dir="ltr" autocapitalize="none" maxlength="32" :aria-invalid="invalid || undefined" />
        </UField>
        <UField label="التخصص في الشركة">
          <USegment v-model="form.specialty" :options="[{ value: null, label: 'بلا' }, ...Object.entries(SPECIALTIES).map(([value, label]) => ({ value, label }))]" label="التخصص" />
        </UField>
        <UField label="الدور" :error="errors.role">
          <USegment
            v-model="form.role"
            :options="[
              { value: 'member', label: 'عضو' },
              { value: 'manager', label: 'مدير' },
            ]"
            label="الدور"
          />
        </UField>
        <div class="grid grid-cols-2 gap-4">
          <UField v-slot="{ id }" label="الجوال" optional><input :id="id" v-model="form.phone" class="input" dir="ltr" inputmode="tel" maxlength="30" /></UField>
          <UField label="اللون">
            <div class="flex flex-wrap gap-1.5" role="radiogroup" aria-label="اللون">
              <button
                v-for="c in COLORS"
                :key="c"
                type="button"
                role="radio"
                :aria-checked="form.color === c"
                :aria-label="c"
                class="size-8 rounded-full ring-offset-2 ring-offset-card"
                :class="form.color === c && 'ring-2 ring-ink'"
                :style="{ background: c }"
                @click="form.color = c"
              />
            </div>
          </UField>
        </div>
      </form>
      <template #footer>
        <UButton type="submit" form="member-form" :loading="saving" class="flex-1">{{ editing ? 'حفظ' : 'إضافة العضو' }}</UButton>
        <UButton variant="secondary" @click="formOpen = false">إلغاء</UButton>
      </template>
    </UDialog>

    <UDialog :open="Boolean(credentials)" title="بيانات الدخول" @close="credentials = null">
      <div v-if="credentials" class="space-y-3 pb-2">
        <p class="text-[14.5px]">أرسلها إلى <strong>{{ credentials.name }}</strong>. سيُطلب منه تغيير كلمة المرور عند أول دخول. لن تظهر كلمة المرور مرة أخرى.</p>
        <dl class="space-y-2 rounded-[12px] bg-sunken p-4" dir="ltr">
          <div class="flex justify-between gap-3"><dt class="text-muted">Username</dt><dd class="font-semibold">{{ credentials.username }}</dd></div>
          <div class="flex justify-between gap-3"><dt class="text-muted">Password</dt><dd class="num font-semibold">{{ credentials.password }}</dd></div>
        </dl>
      </div>
      <template #footer>
        <UButton :icon="Copy" class="flex-1" @click="copyCreds">نسخ</UButton>
        <UButton variant="secondary" @click="credentials = null">تم</UButton>
      </template>
    </UDialog>

    <UDialog :open="Boolean(viewing)" :title="viewing?.name || ''" @close="viewing = null">
      <div v-if="viewing" class="space-y-3 pb-2 text-[14.5px]">
        <p class="text-muted" dir="auto">{{ viewing.role === 'manager' ? 'مدير' : 'عضو' }} · {{ viewing.specialty ? SPECIALTIES[viewing.specialty] : 'بلا تخصص' }}<template v-if="viewing.phone">&nbsp;· <span dir="ltr">{{ viewing.phone }}</span></template></p>
        <div>
          <p class="font-medium">الأوقات الثابتة</p>
          <ul v-if="viewing.slots.length" class="mt-1 space-y-1">
            <li v-for="s in viewing.slots" :key="s.id">{{ DAY_NAMES[s.dow] }}: <span class="num">{{ formatTime(s.startTime) }} – {{ formatTime(s.endTime) }}</span> ({{ s.label || SLOT_KINDS[s.kind] }})</li>
          </ul>
          <p v-else class="text-muted">لا توجد</p>
        </div>
        <div v-if="viewing.absences.length">
          <p class="font-medium">الغياب القادم</p>
          <ul class="mt-1 space-y-1">
            <li v-for="a in viewing.absences" :key="a.id">{{ formatDate(a.startDate) }} – {{ formatDate(a.endDate) }}<span v-if="a.reason" class="text-muted"> · {{ a.reason }}</span></li>
          </ul>
        </div>
        <p class="text-muted">رصيد التوزيع المرحّل: <span class="num" dir="ltr">{{ Number(viewing.distributionBalance.toFixed(1)) }}</span></p>
      </div>
    </UDialog>

    <SlotsEditor :open="Boolean(slotsFor)" :user-id="slotsFor?.id" :slots="slotsFor?.slots || []" :title="`أوقات ${slotsFor?.name || ''} الثابتة`" @close="slotsFor = null" />
  </div>
</template>
