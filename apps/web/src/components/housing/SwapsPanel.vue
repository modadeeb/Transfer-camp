<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { ArrowLeftRight, Plus } from 'lucide-vue-next';
import { get, post } from '../../lib/api.js';
import { relativeDay, timeAgo } from '../../lib/format.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import UBadge from '../ui/UBadge.vue';
import UButton from '../ui/UButton.vue';
import UEmpty from '../ui/UEmpty.vue';
import USkeleton from '../ui/USkeleton.vue';

const session = useSession();
const ui = useUi();
const swaps = ref(null);
const showAll = ref(false);
async function load() {
  try {
    swaps.value = (await get('/swaps', { all: showAll.value ? 1 : undefined })).swaps;
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(showAll, load);
watch(() => [ui.versions.housing, ui.versions.tasks], load);

const STATUS = { pending: ['بانتظار الرد', 'brass'], accepted: ['قُبل', 'sage'], rejected: ['رُفض', 'neutral'], cancelled: ['أُلغي', 'neutral'] };
const me = computed(() => session.user.id);

async function decide(s, decision) {
  if (decision === 'cancel' && !(await ui.confirm({ title: 'إلغاء الطلب؟', confirmLabel: 'إلغاء الطلب' }))) return;
  try {
    await post(`/swaps/${s.id}/${decision}`);
    ui.toast({ accept: 'قبلت التبديل؛ المهمة صارت لك', reject: 'رفضت الطلب', cancel: 'أُلغي الطلب' }[decision]);
    ui.bump('tasks', 'housing');
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-[14px] text-muted">اطلب من زميل أن يأخذ مهمتك، أو تبادلا مهمتين. النقاط تنتقل تلقائياً عند القبول.</p>
      <div class="flex gap-2">
        <UButton v-if="session.isManager" variant="ghost" size="sm" :aria-pressed="showAll" @click="showAll = !showAll">{{ showAll ? 'طلباتي فقط' : 'كل الطلبات' }}</UButton>
        <UButton :icon="Plus" @click="ui.quickAdd = 'swap'">طلب تبديل</UButton>
      </div>
    </div>
    <USkeleton v-if="!swaps" :lines="3" />
    <section v-else-if="swaps.length" class="section">
      <ul class="divide-y divide-line">
        <li v-for="s in swaps" :key="s.id" class="flex flex-wrap items-center gap-3 px-4 py-3">
          <ArrowLeftRight class="size-5 shrink-0 text-sage" />
          <div class="min-w-0 flex-1">
            <p class="text-[14.5px]">
              <strong>{{ s.fromUserId === me ? 'أنت' : s.fromName }}</strong> ← <strong>{{ s.toUserId === me ? 'أنت' : s.toName }}</strong>:
              «{{ s.taskTitle }}» {{ relativeDay(s.taskDueDate) }}
              <template v-if="s.counterTitle">&nbsp;مقابل «{{ s.counterTitle }}» {{ relativeDay(s.counterDueDate) }}</template>
            </p>
            <p class="text-[13px] text-muted">{{ timeAgo(s.createdAt) }}<template v-if="s.note">&nbsp;· {{ s.note }}</template></p>
          </div>
          <UBadge :tone="STATUS[s.status][1]">{{ STATUS[s.status][0] }}</UBadge>
          <div v-if="s.status === 'pending'" class="flex gap-2">
            <template v-if="s.toUserId === me">
              <UButton size="sm" @click="decide(s, 'accept')">قبول</UButton>
              <UButton size="sm" variant="secondary" @click="decide(s, 'reject')">رفض</UButton>
            </template>
            <UButton v-else-if="s.fromUserId === me || session.isManager" size="sm" variant="secondary" @click="decide(s, 'cancel')">إلغاء</UButton>
          </div>
        </li>
      </ul>
    </section>
    <UEmpty v-else :icon="ArrowLeftRight" title="لا توجد طلبات تبديل" body="عندما يتعارض موعد مهمتك مع ظرف طارئ، اطلب من زميل التبديل." />
  </div>
</template>
