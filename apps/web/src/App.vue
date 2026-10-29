<script setup>
import { onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from './components/layout/AppShell.vue';
import ConfirmHost from './components/ui/ConfirmHost.vue';
import Toaster from './components/ui/Toaster.vue';
import UpdateBanner from './components/layout/UpdateBanner.vue';
import { setUnauthorizedHandler } from './lib/api.js';
import { useSession } from './stores/session.js';
import { useUi } from './stores/ui.js';

const route = useRoute();
const router = useRouter();
const session = useSession();
const ui = useUi();

setUnauthorizedHandler(() => {
  if (!session.user) return;
  session.user = null;
  ui.toast('انتهت الجلسة. سجّل الدخول مرة أخرى', { type: 'error' });
  router.replace({ name: 'login' });
});

onMounted(() => {
  const mq = window.matchMedia('(min-width: 1024px)');
  mq.addEventListener('change', (e) => (ui.isDesktop = e.matches));
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => session.applyTheme());
  navigator.serviceWorker?.addEventListener('message', (e) => {
    if (e.data?.type === 'navigate' && e.data.link) router.push(e.data.link);
  });
});
</script>

<template>
  <AppShell v-if="session.user && !route.meta.public && !route.meta.bare">
    <RouterView />
  </AppShell>
  <RouterView v-else />
  <Toaster />
  <ConfirmHost />
  <UpdateBanner />
</template>
