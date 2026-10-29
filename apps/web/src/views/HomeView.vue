<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { ArrowLeftRight, CalendarClock, Dumbbell, HandCoins, Inbox, Moon, Plus, ThumbsUp, TriangleAlert } from 'lucide-vue-next';
import { formatDate, formatDuration, formatTime, sleepMinutes } from '@camp/domain';
import PrayerRow from '../components/PrayerRow.vue';
import TaskDialogs from '../components/tasks/TaskDialogs.vue';
import TaskRow from '../components/tasks/TaskRow.vue';
import Money from '../components/ui/Money.vue';
import SectionCard from '../components/ui/SectionCard.vue';
import UButton from '../components/ui/UButton.vue';
import UEmpty from '../components/ui/UEmpty.vue';
import UProgress from '../components/ui/UProgress.vue';
import USkeleton from '../components/ui/USkeleton.vue';
import { get, post, put } from '../lib/api.js';
import { TASKS, count, greeting, relativeDay } from '../lib/format.js';
import { PRAYERS, nextPrayer, prayerTimes } from '../lib/prayers.js';
import { useTaskActions } from '../lib/useTaskActions.js';
import { useSession } from '../stores/session.js';
import { useUi } from '../stores/ui.js';

const session = useSession();
const ui = useUi();
const data = ref(null);
const failed = ref(false);
const ta = useTaskActions(() => load());

async function load() {
  try {
    data.value = await get('/home');
    failed.value = false;
  } catch (e) {
    if (!data.value) failed.value = true;
    else ui.error(e);
  }
}
onMounted(load);
watch(() => [ui.versions.tasks, ui.versions.budget, ui.versions.personal, ui.versions.money], load);

const firstName = computed(() => session.user.name.split(' ')[0]);
const next = computed(() => (data.value ? nextPrayer(data.value.today, data.value.nowTime) : null));
const nextTime = computed(() => (data.value && next.value ? prayerTimes(data.value.today)[next.value.key] : null));
const doneToday = computed(() => (data.value ? data.value.tasks.filter((t) => t.dueDate === data.value.today && t.status === 'approved').length : 0));
const totalToday = computed(() => (data.value ? data.value.tasks.filter((t) => t.dueDate === data.value.today).length : 0));
const sleepText = computed(() => (data.value?.sleep ? formatDuration(sleepMinutes(data.value.sleep.sleptAt, data.value.sleep.wokeAt)) : '—'));
const workoutGoal = computed(() => session.settings.workoutsPerWeek ?? 4);

async function togglePrayer(key) {
  const done = data.value.prayers.includes(key);
  data.value.prayers = done ? data.value.prayers.filter((p) => p !== key) : [...data.value.prayers, key];
  try {
    await put('/me/prayers', { date: data.value.today, prayer: key, done: !done });
  } catch (e) {
    data.value.prayers = done ? [...data.value.prayers, key] : data.value.prayers.filter((p) => p !== key);
    ui.error(e);
  }
}

async function answerSwap(s, decision) {
  try {
    await post(`/swaps/${s.id}/${decision}`);
    ui.toast(decision === 'accept' ? 'قبلت التبديل؛ المهمة صارت لك' : 'رفضت الطلب');
    ui.bump('tasks', 'housing');
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div v-if="failed" class="section">
    <UEmpty title="تعذّر تحميل الصفحة" body="تحقق من الاتصال ثم حاول مرة أخرى."><UButton @click="load">حاول مرة أخرى</UButton></UEmpty>
  </div>
  <USkeleton v-else-if="!data" :lines="6" />
  <div v-else class="space-y-5">
    <!-- Greeting: the day at a glance, next prayer in brass -->
    <header class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p class="text-muted">{{ formatDate(data.today, { weekday: true, year: true }) }}</p>
        <h1 class="mt-1 text-[28px] font-bold leading-tight lg:text-[34px]">{{ greeting(data.nowTime) }}، {{ firstName }}</h1>
        <p v-if="next" class="mt-2 inline-flex items-center gap-2 text-[15px]">
          <span class="size-2.5 rounded-full bg-brass" aria-hidden="true" />
          الصلاة القادمة <strong>{{ next.name }}</strong> <span class="num text-[color:var(--brass)]">{{ formatTime(nextTime) }}</span>
        </p>
      </div>
      <div class="hidden sm:block"><UButton :icon="Plus" @click="ui.quickAdd = 'task'">{{ session.isManager ? 'إضافة مهمة' : 'مهمة شخصية' }}</UButton></div>
    </header>

    <!-- Things waiting for me -->
    <div v-if="data.swaps.length || data.contributionsDue.length || data.manager?.pendingApprovals || data.manager?.overdue || data.manager?.nextWeekDistribution === 'draft'" class="space-y-2">
      <div v-for="s in data.swaps" :key="s.id" class="flex flex-wrap items-center gap-3 rounded-[12px] border border-brass/40 bg-brass-soft px-4 py-3">
        <ArrowLeftRight class="size-5 shrink-0 text-[color:var(--brass)]" />
        <p class="min-w-0 flex-1 text-[14.5px]">
          <strong>{{ s.fromName }}</strong> يطلب منك «{{ s.taskTitle }}» {{ relativeDay(s.taskDueDate) }}<span v-if="s.note" class="text-muted"> — {{ s.note }}</span>
        </p>
        <div class="flex gap-2">
          <UButton size="sm" @click="answerSwap(s, 'accept')">قبول</UButton>
          <UButton size="sm" variant="secondary" @click="answerSwap(s, 'reject')">رفض</UButton>
        </div>
      </div>
      <RouterLink v-for="c in data.contributionsDue" :key="`c${c.id}`" to="/money" class="flex items-center gap-3 rounded-[12px] border border-line bg-card px-4 py-3 hover:bg-sunken">
        <HandCoins class="size-5 shrink-0 text-[color:var(--brass)]" />
        <span class="flex-1 text-[14.5px]">مساهمة الصندوق «{{ c.title }}»: المتبقي عليك <Money :amount="c.remaining" /></span>
        <span v-if="c.overdue" class="chip bg-danger-soft text-danger">متأخرة</span>
      </RouterLink>
      <RouterLink v-if="data.manager?.pendingApprovals" to="/work?tab=manage&status=submitted" class="flex items-center gap-3 rounded-[12px] border border-line bg-card px-4 py-3 hover:bg-sunken">
        <ThumbsUp class="size-5 shrink-0 text-sage" />
        <span class="num flex-1 text-[14.5px]">{{ count(data.manager.pendingApprovals, TASKS) }} بانتظار اعتمادك</span>
      </RouterLink>
      <RouterLink v-if="data.manager?.overdue" to="/work?tab=manage&overdue=1" class="flex items-center gap-3 rounded-[12px] border border-line bg-card px-4 py-3 hover:bg-sunken">
        <TriangleAlert class="size-5 shrink-0 text-danger" />
        <span class="num flex-1 text-[14.5px]">{{ count(data.manager.overdue, TASKS) }} تجاوزت موعدها</span>
      </RouterLink>
      <RouterLink v-if="data.manager?.nextWeekDistribution === 'draft'" to="/housing?tab=distribution&next=1" class="flex items-center gap-3 rounded-[12px] border border-line bg-card px-4 py-3 hover:bg-sunken">
        <CalendarClock class="size-5 shrink-0 text-sage" />
        <span class="flex-1 text-[14.5px]">مسودة توزيع الأسبوع القادم جاهزة للمراجعة والنشر</span>
      </RouterLink>
    </div>

    <!-- Summary strip -->
    <dl class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
      <div class="section px-4 py-3">
        <dt class="text-[13px] text-muted">مهام اليوم</dt>
        <dd class="num mt-1 text-[22px] font-semibold">{{ doneToday }}<span class="text-[15px] font-normal text-muted"> / {{ totalToday }}</span></dd>
      </div>
      <div class="section px-4 py-3">
        <dt class="text-[13px] text-muted">مسموح اليوم</dt>
        <dd class="mt-1 text-[22px] font-semibold"><Money v-if="data.budget" :amount="data.budget.summary.leftToday" :unit="false" /><span v-else class="text-[15px] font-normal text-muted">لم يبدأ أسبوعك</span></dd>
      </div>
      <div class="section px-4 py-3">
        <dt class="text-[13px] text-muted">نقاط السكن هذا الأسبوع</dt>
        <dd class="num mt-1 text-[22px] font-semibold">{{ data.housePoints.done }}<span class="text-[15px] font-normal text-muted"> / {{ data.housePoints.pts }}</span></dd>
      </div>
      <div class="section px-4 py-3">
        <dt class="text-[13px] text-muted">العادات</dt>
        <dd class="num mt-1 text-[22px] font-semibold">{{ data.habits.done }}<span class="text-[15px] font-normal text-muted"> / {{ data.habits.due }}</span></dd>
      </div>
      <div class="section col-span-2 px-4 py-3 sm:col-span-1">
        <dt class="text-[13px] text-muted">النوم الليلة الماضية</dt>
        <dd class="num mt-1 text-[22px] font-semibold">{{ sleepText }}</dd>
      </div>
    </dl>

    <div class="grid gap-5 lg:grid-cols-[1.35fr_1fr]">
      <div class="space-y-5">
        <SectionCard title="مهامي اليوم" :subtitle="data.tasks.some((t) => t.dueDate < data.today) ? 'تشمل مهاماً من أيام سابقة لم تكتمل بعد' : ''" flush>
          <template #action>
            <RouterLink to="/me?tab=schedule" class="rounded-md px-2 py-1 text-[14px] text-link hover:bg-sunken">جدولي</RouterLink>
          </template>
          <ul v-if="data.tasks.length" class="px-2 pb-2">
            <TaskRow v-for="t in data.tasks" :key="t.id" :task="t" :ta="ta" :show-date="t.dueDate !== data.today" />
          </ul>
          <UEmpty v-else :icon="Inbox" title="لا مهام لك اليوم" body="يوم هادئ. أضف مهمة شخصية إن أردت تنظيم وقتك." />
        </SectionCard>

        <SectionCard v-if="data.events.length" title="اليوم في المعسكر">
          <ul class="space-y-2">
            <li v-for="e in data.events" :key="e.id" class="flex items-center gap-3">
              <span class="num w-20 shrink-0 text-[13.5px] text-muted">{{ e.startTime ? formatTime(e.startTime) : 'طوال اليوم' }}</span>
              <span class="font-medium">{{ e.title }}</span>
            </li>
          </ul>
        </SectionCard>
      </div>

      <div class="space-y-5">
        <SectionCard title="الصلوات اليوم" :subtitle="`${data.prayers.length} من 5`">
          <PrayerRow :date="data.today" :done="data.prayers" :now="data.nowTime" is-today @toggle="togglePrayer" />
        </SectionCard>

        <SectionCard title="مصروف اليوم">
          <template #action>
            <UButton size="sm" variant="soft" :icon="Plus" @click="ui.quickAdd = 'personalExpense'">مصروف</UButton>
          </template>
          <div v-if="data.budget" class="space-y-3">
            <dl class="grid grid-cols-3 gap-2 text-center">
              <div><dt class="text-[13px] text-muted">المسموح</dt><dd class="font-semibold"><Money :amount="data.budget.summary.allowedToday" :unit="false" /></dd></div>
              <div><dt class="text-[13px] text-muted">صرفت</dt><dd class="font-semibold"><Money :amount="data.budget.summary.spentToday" :unit="false" /></dd></div>
              <div>
                <dt class="text-[13px] text-muted">{{ data.budget.summary.overToday ? 'تجاوزت' : 'المتبقي' }}</dt>
                <dd class="font-semibold" :class="data.budget.summary.overToday && 'text-danger'"><Money :amount="data.budget.summary.overToday || data.budget.summary.leftToday" :unit="false" /></dd>
              </div>
            </dl>
            <UProgress
              :value="data.budget.summary.allowedToday > 0 ? (data.budget.summary.spentToday / data.budget.summary.allowedToday) * 100 : 0"
              :tone="data.budget.summary.overToday ? 'danger' : 'sage'"
              label="المصروف من المسموح اليوم"
            />
            <p v-if="data.budget.summary.overToday" class="text-[13px] text-muted">لا بأس، يُوزَّع الفرق على الأيام القادمة.</p>
          </div>
          <div v-else class="text-center">
            <p class="text-[14.5px] text-muted">ابدأ أسبوعك بإدخال دخلك والأساسيات، فيُحسب مسموحك اليومي تلقائياً.</p>
            <RouterLink to="/money?tab=budget" class="mt-3 inline-flex h-10 items-center rounded-[10px] bg-primary px-4 font-medium text-on-primary">ابدأ الأسبوع</RouterLink>
          </div>
        </SectionCard>

        <SectionCard title="صحتي">
          <div class="grid grid-cols-2 gap-3">
            <RouterLink to="/me?tab=health" class="rounded-[12px] bg-sunken p-3 hover:brightness-95">
              <Moon class="size-5 text-sage" />
              <p class="mt-2 text-[13px] text-muted">النوم</p>
              <p class="num font-semibold">{{ data.sleep ? `${formatTime(data.sleep.sleptAt)} ← ${formatTime(data.sleep.wokeAt)}` : 'سجّل نومك' }}</p>
            </RouterLink>
            <RouterLink to="/me?tab=health" class="rounded-[12px] bg-sunken p-3 hover:brightness-95">
              <Dumbbell class="size-5 text-sage" />
              <p class="mt-2 text-[13px] text-muted">الرياضة هذا الأسبوع</p>
              <p class="num font-semibold">{{ data.workoutsThisWeek }} من {{ workoutGoal }}</p>
            </RouterLink>
          </div>
        </SectionCard>
      </div>
    </div>
    <TaskDialogs :ta="ta" />
  </div>
</template>
