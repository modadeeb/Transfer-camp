<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { CalendarHeart, Plus } from 'lucide-vue-next';
import { addDays, adenDate, formatDate, formatTime } from '@camp/domain';
import { actions } from '../../lib/actions.js';
import { del, get, patch, post } from '../../lib/api.js';
import { useForm } from '../../lib/useForm.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import MemberPicker from '../ui/MemberPicker.vue';
import RowActions from '../ui/RowActions.vue';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UEmpty from '../ui/UEmpty.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const events = ref(null);
const past = ref(false);
const formOpen = ref(false);
const editing = ref(null);
const viewing = ref(null);
const KINDS = { meeting: 'اجتماع', deadline: 'موعد تسليم', other: 'أخرى' };
const blank = () => ({ title: '', kind: 'meeting', date: adenDate(), startTime: '', endTime: '', everyone: true, memberIds: [], notes: '' });
const { form, errors, saving, submit, reset } = useForm(blank());

async function load() {
  try {
    const today = adenDate();
    events.value = (await get('/events', past.value ? { from: addDays(today, -90), to: addDays(today, -1) } : { from: today })).events;
    if (past.value) events.value.reverse();
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(past, load);
watch(() => ui.versions.housing, load);

function openForm(e = null) {
  editing.value = e;
  reset(e ? { ...blank(), ...e, startTime: e.startTime || '', endTime: e.endTime || '', notes: e.notes || '' } : blank());
  formOpen.value = true;
}
async function save() {
  const body = { title: form.title, kind: form.kind, date: form.date, startTime: form.startTime || null, endTime: form.endTime || null, everyone: form.everyone, memberIds: form.everyone ? [] : form.memberIds, notes: form.notes || null };
  const r = await submit(() => (editing.value ? patch(`/events/${editing.value.id}`, body) : post('/events', body)));
  if (!r) return;
  ui.toast(editing.value ? 'حُفظ الحدث' : 'أُضيف الحدث إلى جدول المجموعة');
  formOpen.value = false;
  ui.bump('housing');
}
const who = (e) => (e.everyone ? 'الجميع' : e.memberIds.map((id) => session.memberName(id)).join('، '));
const itemsFor = () => (session.isManager ? actions(['view', 'edit', 'copy', 'delete']) : actions(['view']));
async function run(e, key) {
  try {
    if (key === 'view') viewing.value = e;
    else if (key === 'edit') openForm(e);
    else if (key === 'copy') {
      await post(`/events/${e.id}/copy`);
      ui.toast('نُسخ الحدث');
      ui.bump('housing');
    } else if (key === 'delete') {
      if (await ui.confirm({ title: `حذف «${e.title}»؟`, confirmLabel: 'حذف', danger: true })) {
        await ui.deleteWithUndo({ remove: () => del(`/events/${e.id}`), restore: () => post(`/events/${e.id}/restore`), message: 'حُذف الحدث', after: () => ui.bump('housing') });
      }
    }
  } catch (err) {
    ui.error(err);
  }
}
const grouped = computed(() => {
  const map = new Map();
  for (const e of events.value || []) map.set(e.date, [...(map.get(e.date) || []), e]);
  return [...map.entries()];
});
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <USegment
        v-model="past"
        :options="[
          { value: false, label: 'القادمة' },
          { value: true, label: 'السابقة' },
        ]"
        label="الأحداث"
      />
      <UButton v-if="session.isManager" :icon="Plus" @click="openForm()">اجتماع أو موعد</UButton>
    </div>
    <USkeleton v-if="!events" :lines="3" />
    <div v-else-if="events.length" class="space-y-3">
      <section v-for="[date, list] in grouped" :key="date" class="section">
        <h3 class="px-4 pt-3 font-semibold">{{ formatDate(date, { weekday: true }) }}</h3>
        <ul class="divide-y divide-line px-2 pb-1">
          <li v-for="e in list" :key="e.id" class="flex items-center gap-3 px-2 py-3">
            <span class="num w-24 shrink-0 text-[13.5px] text-muted">{{ e.startTime ? formatTime(e.startTime) : 'طوال اليوم' }}</span>
            <div class="min-w-0 flex-1">
              <p class="font-medium">{{ e.title }}</p>
              <p class="truncate text-[13px] text-muted">{{ who(e) }}</p>
            </div>
            <UBadge :tone="e.kind === 'deadline' ? 'brass' : 'sage'">{{ KINDS[e.kind] }}</UBadge>
            <RowActions :items="itemsFor(e)" @action="run(e, $event)" />
          </li>
        </ul>
      </section>
    </div>
    <UEmpty v-else :icon="CalendarHeart" :title="past ? 'لا أحداث سابقة' : 'لا اجتماعات أو مواعيد قادمة'" />

    <UDialog :open="formOpen" :title="editing ? 'تعديل الحدث' : 'اجتماع أو موعد'" @close="formOpen = false">
      <form id="event-form" class="space-y-4" @submit.prevent="save">
        <UField v-slot="{ id, invalid }" label="العنوان" :error="errors.title"><input :id="id" v-model="form.title" class="input" maxlength="100" :aria-invalid="invalid || undefined" placeholder="مثال: اجتماع الفريق الأسبوعي" /></UField>
        <UField label="النوع"><USegment v-model="form.kind" :options="Object.entries(KINDS).map(([value, label]) => ({ value, label }))" label="النوع" /></UField>
        <div class="grid grid-cols-3 gap-3">
          <UField v-slot="{ id }" label="التاريخ" :error="errors.date"><input :id="id" v-model="form.date" type="date" class="input" /></UField>
          <UField v-slot="{ id }" label="من" optional><input :id="id" v-model="form.startTime" type="time" class="input" /></UField>
          <UField v-slot="{ id }" label="إلى" optional :error="errors.endTime"><input :id="id" v-model="form.endTime" type="time" class="input" /></UField>
        </div>
        <UField label="الحضور" :error="errors.memberIds">
          <USegment
            v-model="form.everyone"
            :options="[
              { value: true, label: 'الجميع' },
              { value: false, label: 'أعضاء محددون' },
            ]"
            label="الحضور"
          />
          <MemberPicker v-if="!form.everyone" v-model="form.memberIds" multiple class="mt-2" />
        </UField>
        <UField v-slot="{ id }" label="ملاحظات" optional><textarea :id="id" v-model="form.notes" class="input" maxlength="1000" /></UField>
      </form>
      <template #footer>
        <UButton type="submit" form="event-form" :loading="saving" class="flex-1">حفظ</UButton>
        <UButton variant="secondary" @click="formOpen = false">إلغاء</UButton>
      </template>
    </UDialog>
    <UDialog :open="Boolean(viewing)" :title="viewing?.title || ''" @close="viewing = null">
      <dl v-if="viewing" class="space-y-2 pb-2 text-[14.5px]">
        <div><dt class="text-muted">الموعد</dt><dd>{{ formatDate(viewing.date, { weekday: true }) }} {{ viewing.startTime ? formatTime(viewing.startTime) : '' }}{{ viewing.endTime ? ` – ${formatTime(viewing.endTime)}` : '' }}</dd></div>
        <div><dt class="text-muted">الحضور</dt><dd>{{ who(viewing) }}</dd></div>
        <div v-if="viewing.notes"><dt class="text-muted">ملاحظات</dt><dd class="whitespace-pre-line">{{ viewing.notes }}</dd></div>
      </dl>
    </UDialog>
  </div>
</template>
