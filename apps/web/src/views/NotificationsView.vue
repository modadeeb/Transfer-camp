<script setup>
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { BellOff, CheckCheck, Trash2 } from 'lucide-vue-next';
import UButton from '../components/ui/UButton.vue';
import UEmpty from '../components/ui/UEmpty.vue';
import USkeleton from '../components/ui/USkeleton.vue';
import { timeAgo } from '../lib/format.js';
import { useNotifications } from '../stores/notifications.js';
import { useUi } from '../stores/ui.js';

const store = useNotifications();
const ui = useUi();
const router = useRouter();
onMounted(() => store.load());

async function openItem(n) {
  await store.markRead(n);
  if (n.link) router.push(n.link);
}
async function remove(n) {
  try {
    await store.remove(n);
    ui.toast('حُذف الإشعار', { action: { label: 'تراجع', run: () => store.restore(n) } });
  } catch (e) {
    ui.error(e);
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-4">
    <div class="flex items-center justify-between gap-3">
      <h1 class="text-[24px] font-bold">الإشعارات</h1>
      <UButton v-if="store.unread" variant="ghost" size="sm" :icon="CheckCheck" @click="store.markAll()">تعليم الكل كمقروء</UButton>
    </div>
    <USkeleton v-if="store.loading && !store.items.length" :lines="5" />
    <section v-else-if="store.items.length" class="section">
      <ul class="divide-y divide-line">
        <li v-for="n in store.items" :key="n.id" class="flex items-start gap-3 px-4 py-3" :class="!n.readAt && 'bg-sage-soft/50'">
          <span class="mt-2 size-2 shrink-0 rounded-full" :class="n.readAt ? 'bg-transparent' : n.urgent ? 'bg-danger' : 'bg-brass'" aria-hidden="true" />
          <button type="button" class="min-w-0 flex-1 text-start" @click="openItem(n)">
            <p class="font-medium">{{ n.title }}<span v-if="!n.readAt" class="sr-only"> (جديد)</span></p>
            <p v-if="n.body" class="text-[14px] text-muted">{{ n.body }}</p>
            <p class="mt-0.5 text-[12.5px] text-muted">{{ store.types[n.type] || '' }} · {{ timeAgo(n.createdAt) }}</p>
          </button>
          <button type="button" class="grid size-8 shrink-0 place-items-center rounded-full text-muted hover:text-danger" aria-label="حذف الإشعار" @click="remove(n)"><Trash2 class="size-4" /></button>
        </li>
      </ul>
    </section>
    <UEmpty v-else :icon="BellOff" title="لا إشعارات" body="ستصلك هنا المهام الجديدة والتذكيرات وطلبات التبديل." />
  </div>
</template>
