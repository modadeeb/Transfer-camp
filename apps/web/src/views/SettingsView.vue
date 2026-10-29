<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { BellRing, Download, LogOut, RotateCcw, Trash2 } from 'lucide-vue-next';
import MembersAdmin from '../components/settings/MembersAdmin.vue';
import SectionCard from '../components/ui/SectionCard.vue';
import UButton from '../components/ui/UButton.vue';
import UEmpty from '../components/ui/UEmpty.vue';
import UField from '../components/ui/UField.vue';
import USegment from '../components/ui/USegment.vue';
import UTabs from '../components/ui/UTabs.vue';
import { get, patch, post } from '../lib/api.js';
import { timeAgo } from '../lib/format.js';
import { disablePush, enablePush, pushState } from '../lib/push.js';
import { useForm } from '../lib/useForm.js';
import { useTab } from '../lib/useTab.js';
import { useNotifications } from '../stores/notifications.js';
import { useSession } from '../stores/session.js';
import { useUi } from '../stores/ui.js';

const session = useSession();
const ui = useUi();
const router = useRouter();
const notifications = useNotifications();
const tabs = computed(() => [
  { key: 'profile', label: 'الملف الشخصي' },
  { key: 'notifications', label: 'الإشعارات' },
  { key: 'appearance', label: 'المظهر' },
  ...(session.isManager ? [{ key: 'members', label: 'الأعضاء' }, { key: 'camp', label: 'المعسكر' }] : []),
  { key: 'trash', label: 'المحذوفات' },
  { key: 'data', label: 'البيانات' },
]);
const tab = useTab(() => tabs.value, 'profile');

// profile
const profile = useForm({ name: session.user.name, phone: session.user.phone || '', sleepFrom: session.settings.sleepFrom || '23:00', sleepTo: session.settings.sleepTo || '06:00', workoutsPerWeek: session.settings.workoutsPerWeek ?? 4 });
async function saveProfile() {
  const f = profile.form;
  const r = await profile.submit(() => patch('/me', { name: f.name, phone: f.phone || null, settings: { sleepFrom: f.sleepFrom, sleepTo: f.sleepTo, workoutsPerWeek: Number(f.workoutsPerWeek) } }));
  if (!r) return;
  session.setUser(r.user);
  await session.loadMembers();
  ui.toast('حُفظ ملفك');
  ui.bump('personal');
}
const pw = useForm({ current: '', password: '', confirm: '' });
const pwMismatch = ref('');
async function savePassword() {
  pwMismatch.value = pw.form.password !== pw.form.confirm ? 'كلمتا المرور غير متطابقتين' : '';
  if (pwMismatch.value) return;
  const r = await pw.submit(() => post('/auth/password', { current: pw.form.current, password: pw.form.password }));
  if (!r) return;
  pw.reset();
  ui.toast('تغيّرت كلمة المرور · خرجت أجهزتك الأخرى');
}

// notifications
const push = ref(pushState());
const pushBusy = ref(false);
const prefs = ref({ disabled: [...(session.settings.notifications?.disabled || [])], quietFrom: session.settings.notifications?.quietFrom || '', quietTo: session.settings.notifications?.quietTo || '' });
const PUSH_TEXT = {
  on: 'مفعّلة على هذا الجهاز',
  off: 'غير مفعّلة على هذا الجهاز',
  denied: 'المتصفح يمنع الإشعارات. فعّلها من إعدادات المتصفح لهذا الموقع.',
  unsupported: 'هذا المتصفح لا يدعم الإشعارات.',
  'install-first': 'على الآيفون: أضف التطبيق إلى الشاشة الرئيسية أولاً (زر المشاركة ← إضافة إلى الشاشة الرئيسية)، ثم افتحه من هناك وفعّل الإشعارات.',
  'not-configured': 'لم يُضبط Firebase على الخادم بعد. اطلب من المدير إكمال إعداد الإشعارات.',
  error: 'تعذّر تفعيل الإشعارات. حاول مرة أخرى.',
};
async function togglePush() {
  pushBusy.value = true;
  try {
    push.value = push.value === 'on' ? await disablePush() : await enablePush();
    if (push.value === 'on') ui.toast('فُعّلت الإشعارات على هذا الجهاز');
  } catch (e) {
    push.value = 'error';
    ui.error(e);
  } finally {
    pushBusy.value = false;
  }
}
const testing = ref(false);
async function sendTest() {
  testing.value = true;
  try {
    const r = await post('/push/test');
    notifications.load?.();
    if (!r.configured) ui.toast('وصل الإشعار إلى الجرس 🔔 — إشعارات الجوال تحتاج إكمال إعداد Firebase');
    else if (!r.devices) ui.toast('وصل الإشعار إلى الجرس 🔔 — فعّل الإشعارات على هذا الجهاز أولاً');
    else if (r.sent) ui.toast(`أُرسل إلى ${r.sent === 1 ? 'جهاز واحد' : r.sent === 2 ? 'جهازين' : `${r.sent} أجهزة`} — يفترض أن يظهر خلال ثوانٍ`);
    else ui.toast(r.error || 'تعذّر الإرسال', { type: 'error' });
  } catch (e) {
    ui.error(e);
  } finally {
    testing.value = false;
  }
}
function toggleType(type) {
  const set = new Set(prefs.value.disabled);
  set.has(type) ? set.delete(type) : set.add(type);
  prefs.value.disabled = [...set];
}
async function savePrefs() {
  try {
    const r = await patch('/me', { settings: { notifications: { disabled: prefs.value.disabled, quietFrom: prefs.value.quietFrom || null, quietTo: prefs.value.quietTo || null } } });
    session.setUser(r.user);
    ui.toast('حُفظت تفضيلات الإشعارات');
  } catch (e) {
    ui.error(e);
  }
}
onMounted(() => notifications.types && Object.keys(notifications.types).length === 0 && notifications.load());

// appearance
const theme = ref(session.settings.theme || 'system');
async function saveTheme(value) {
  theme.value = value;
  try {
    localStorage.setItem('camp-theme', value);
  } catch {
    /* ignore */
  }
  try {
    const r = await patch('/me', { settings: { theme: value } });
    session.setUser(r.user);
  } catch (e) {
    ui.error(e);
  }
}

// camp
const campName = ref(session.campName);
async function saveCamp() {
  try {
    const r = await patch('/camp', { campName: campName.value });
    session.campName = r.campName;
    ui.toast('حُفظ اسم المعسكر');
  } catch (e) {
    ui.error(e);
  }
}

// trash
const trash = ref(null);
async function loadTrash() {
  try {
    trash.value = await get('/trash');
  } catch (e) {
    ui.error(e);
  }
}
watch(tab, (t) => t === 'trash' && loadTrash(), { immediate: true });
async function restore(item) {
  try {
    await post('/trash/restore', { entity: item.entity, id: item.id });
    ui.toast(`استُعيد «${item.title}»`);
    ui.bump('tasks', 'housing', 'money', 'personal', 'members');
    if (item.entity === 'user') session.loadMembers();
    loadTrash();
  } catch (e) {
    ui.error(e);
  }
}

async function logout() {
  if (!(await ui.confirm({ title: 'تسجيل الخروج؟', confirmLabel: 'تسجيل الخروج' }))) return;
  await disablePush().catch(() => {});
  await session.logout();
  router.replace('/login');
}
</script>

<template>
  <div class="space-y-5">
    <h1 class="hidden text-[26px] font-bold lg:block">الإعدادات</h1>
    <UTabs v-model="tab" :tabs="tabs" />

    <div v-if="tab === 'profile'" class="grid gap-5 lg:grid-cols-2">
      <SectionCard title="بياناتي">
        <form class="space-y-4" @submit.prevent="saveProfile">
          <UField v-slot="{ id, invalid }" label="الاسم" :error="profile.errors.value.name"><input :id="id" v-model="profile.form.name" class="input" maxlength="60" :aria-invalid="invalid || undefined" /></UField>
          <UField v-slot="{ id }" label="الجوال" optional><input :id="id" v-model="profile.form.phone" class="input" dir="ltr" inputmode="tel" /></UField>
          <div class="grid grid-cols-2 gap-4">
            <UField v-slot="{ id }" label="هدف النوم: من"><input :id="id" v-model="profile.form.sleepFrom" type="time" class="input" /></UField>
            <UField v-slot="{ id }" label="إلى"><input :id="id" v-model="profile.form.sleepTo" type="time" class="input" /></UField>
          </div>
          <UField v-slot="{ id }" label="أيام الرياضة في الأسبوع"><input :id="id" v-model.number="profile.form.workoutsPerWeek" type="number" min="0" max="7" class="input num w-28" /></UField>
          <UButton type="submit" :loading="profile.saving.value">حفظ</UButton>
        </form>
      </SectionCard>
      <SectionCard title="كلمة المرور">
        <form class="space-y-4" @submit.prevent="savePassword">
          <UField v-slot="{ id }" label="الحالية" :error="pw.errors.value.current"><input :id="id" v-model="pw.form.current" type="password" class="input" dir="ltr" autocomplete="current-password" required /></UField>
          <UField v-slot="{ id }" label="الجديدة" hint="8 أحرف على الأقل" :error="pw.errors.value.password"><input :id="id" v-model="pw.form.password" type="password" class="input" dir="ltr" autocomplete="new-password" minlength="8" required /></UField>
          <UField v-slot="{ id }" label="أعد كتابتها" :error="pwMismatch"><input :id="id" v-model="pw.form.confirm" type="password" class="input" dir="ltr" autocomplete="new-password" required /></UField>
          <UButton type="submit" :loading="pw.saving.value">تغيير كلمة المرور</UButton>
        </form>
      </SectionCard>
    </div>

    <div v-else-if="tab === 'notifications'" class="grid gap-5 lg:grid-cols-2">
      <SectionCard title="إشعارات الجوال واللابتوب" subtitle="عبر Firebase">
        <p class="text-[14.5px]" :class="['denied', 'error', 'not-configured'].includes(push) ? 'text-danger' : 'text-muted'">{{ PUSH_TEXT[push] }}</p>
        <UButton v-if="['on', 'off', 'error'].includes(push)" class="mt-4" :variant="push === 'on' ? 'secondary' : 'primary'" :icon="BellRing" :loading="pushBusy" @click="togglePush">
          {{ push === 'on' ? 'إيقاف على هذا الجهاز' : 'تفعيل على هذا الجهاز' }}
        </UButton>
        <UButton class="mt-3" variant="soft" :loading="testing" @click="sendTest">إرسال إشعار تجريبي</UButton>
        <p class="mt-4 text-[13px] text-muted">كل الإشعارات تبقى محفوظة في الجرس داخل التطبيق حتى لو أوقفتها هنا.</p>
      </SectionCard>
      <SectionCard title="ما يصلني">
        <ul class="space-y-2">
          <li v-for="(label, type) in notifications.types" :key="type" class="flex items-center justify-between gap-3">
            <span class="text-[14.5px]">{{ label }}</span>
            <input type="checkbox" class="size-5 accent-[#56856A]" :checked="!prefs.disabled.includes(type)" :aria-label="label" @change="toggleType(type)" />
          </li>
        </ul>
        <div class="mt-5 grid grid-cols-2 gap-4">
          <UField v-slot="{ id }" label="أوقات الهدوء: من" optional><input :id="id" v-model="prefs.quietFrom" type="time" class="input" /></UField>
          <UField v-slot="{ id }" label="إلى" optional><input :id="id" v-model="prefs.quietTo" type="time" class="input" /></UField>
        </div>
        <p class="mt-2 text-[13px] text-muted">في أوقات الهدوء لا يصل إلى جوالك إلا العاجل، والباقي ينتظرك في الجرس.</p>
        <UButton class="mt-4" @click="savePrefs">حفظ</UButton>
      </SectionCard>
    </div>

    <SectionCard v-else-if="tab === 'appearance'" title="المظهر">
      <USegment
        :model-value="theme"
        :options="[
          { value: 'system', label: 'حسب الجهاز' },
          { value: 'light', label: 'فاتح' },
          { value: 'dark', label: 'داكن' },
        ]"
        label="المظهر"
        @update:model-value="saveTheme"
      />
      <label class="mt-5 flex items-center justify-between gap-3">
        <span><span class="block font-medium">إخفاء المبالغ</span><span class="text-[13px] text-muted">تظهر المبالغ كنقاط حتى تضغط زر العين في الأعلى</span></span>
        <input type="checkbox" class="size-5 accent-[#56856A]" :checked="ui.hideAmounts" @change="ui.toggleAmounts()" />
      </label>
    </SectionCard>

    <MembersAdmin v-else-if="tab === 'members'" />

    <SectionCard v-else-if="tab === 'camp'" title="المعسكر">
      <form class="flex flex-wrap items-end gap-3" @submit.prevent="saveCamp">
        <UField v-slot="{ id }" label="اسم المعسكر" class="min-w-60 flex-1"><input :id="id" v-model="campName" class="input" maxlength="60" /></UField>
        <UButton type="submit">حفظ</UButton>
      </form>
    </SectionCard>

    <SectionCard v-else-if="tab === 'trash'" title="المحذوفات" :subtitle="`تُستعاد خلال ${trash?.days || 30} يوماً، ثم تُحذف نهائياً`" flush>
      <ul v-if="trash?.items.length" class="divide-y divide-line px-2 pb-1">
        <li v-for="item in trash.items" :key="`${item.entity}-${item.id}`" class="flex items-center gap-3 px-2 py-3">
          <Trash2 class="size-4 shrink-0 text-muted" />
          <div class="min-w-0 flex-1">
            <p class="truncate font-medium">{{ item.title }}</p>
            <p class="text-[13px] text-muted">{{ item.label }} · حُذف {{ timeAgo(item.deletedAt) }}</p>
          </div>
          <UButton size="sm" variant="soft" :icon="RotateCcw" @click="restore(item)">استعادة</UButton>
        </li>
      </ul>
      <UEmpty v-else-if="trash" :icon="Trash2" title="لا شيء في المحذوفات" />
    </SectionCard>

    <div v-else class="grid gap-5 lg:grid-cols-2">
      <SectionCard title="تصدير بياناتي" subtitle="مهامي وصلواتي ونومي وعاداتي وأهدافي وميزانيتي">
        <a href="/api/me/export" class="inline-flex h-11 items-center gap-2 rounded-[10px] bg-primary px-4 font-medium text-on-primary" download><Download class="size-[18px]" />تنزيل ملف JSON</a>
      </SectionCard>
      <SectionCard title="الجلسة">
        <UButton variant="secondary" :icon="LogOut" @click="logout">تسجيل الخروج</UButton>
      </SectionCard>
    </div>
  </div>
</template>
