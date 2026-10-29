<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import {
  ArrowLeftRight,
  Bell,
  Briefcase,
  CalendarOff,
  ChevronsLeft,
  ChevronsRight,
  ClipboardPlus,
  Eye,
  EyeOff,
  House,
  LayoutDashboard,
  LogOut,
  Plus,
  ReceiptText,
  Settings,
  ShoppingBasket,
  UserRound,
  Wallet,
} from 'lucide-vue-next';
import { adenDate, formatDate } from '@camp/domain';
import { useNotifications } from '../../stores/notifications.js';
import { useSession } from '../../stores/session.js';
import { useUi } from '../../stores/ui.js';
import UAvatar from '../ui/UAvatar.vue';
import UDialog from '../ui/UDialog.vue';
import UMenu from '../ui/UMenu.vue';
import BrandMark from './BrandMark.vue';
import QuickAddHost from './QuickAddHost.vue';

const route = useRoute();
const router = useRouter();
const session = useSession();
const ui = useUi();
const notifications = useNotifications();
const collapsed = ref(localStorage.getItem('camp-sidebar') === '1');
const quickSheet = ref(false);
const today = ref(adenDate());

const nav = [
  { to: '/', name: 'home', label: 'الرئيسية', icon: LayoutDashboard },
  { to: '/housing', name: 'housing', label: 'السكن', icon: House },
  { to: '/work', name: 'work', label: 'العمل', icon: Briefcase },
  { to: '/money', name: 'money', label: 'المال', icon: Wallet },
  { to: '/me', name: 'me', label: 'أنا', icon: UserRound },
];

const quickItems = computed(() => [
  { key: 'task', label: session.isManager ? 'مهمة' : 'مهمة شخصية', icon: ClipboardPlus },
  { key: 'sharedExpense', label: 'مصروف مشترك', icon: ShoppingBasket },
  { key: 'personalExpense', label: 'مصروف شخصي', icon: ReceiptText },
  { key: 'income', label: 'دخل شخصي', icon: Wallet },
  { key: 'swap', label: 'طلب تبديل', icon: ArrowLeftRight },
  { key: 'absence', label: 'تسجيل غياب', icon: CalendarOff },
]);

const profileItems = [
  { key: 'settings', label: 'الإعدادات', icon: Settings },
  { key: 'logout', label: 'تسجيل الخروج', icon: LogOut, danger: true },
];

function toggleSidebar() {
  collapsed.value = !collapsed.value;
  localStorage.setItem('camp-sidebar', collapsed.value ? '1' : '0');
}

function openQuick(key) {
  quickSheet.value = false;
  ui.quickAdd = key;
}

async function onProfile(key) {
  if (key === 'settings') router.push('/settings');
  if (key === 'logout') {
    const ok = await ui.confirm({ title: 'تسجيل الخروج؟', confirmLabel: 'تسجيل الخروج' });
    if (!ok) return;
    await session.logout();
    router.replace('/login');
  }
}

const isActive = (item) => (item.name === 'home' ? route.name === 'home' : route.path.startsWith(item.to));
const title = computed(() => route.meta.title || session.campName);

let dayTimer;
function onVisible() {
  if (document.visibilityState !== 'visible') return;
  notifications.load();
  const d = adenDate();
  if (d !== today.value) {
    today.value = d;
    ui.bump('tasks', 'personal', 'budget', 'housing');
  }
}
onMounted(() => {
  notifications.start();
  document.addEventListener('visibilitychange', onVisible);
  dayTimer = setInterval(onVisible, 60000);
});
onBeforeUnmount(() => {
  notifications.stop();
  document.removeEventListener('visibilitychange', onVisible);
  clearInterval(dayTimer);
});
watch(
  () => ui.versions.notifications,
  () => notifications.load(),
);
</script>

<template>
  <div class="min-h-dvh lg:flex">
    <a href="#main" class="sr-only focus:not-sr-only focus:fixed focus:start-3 focus:top-3 focus:z-[80] focus:rounded-lg focus:bg-card focus:px-3 focus:py-2">تخطَّ إلى المحتوى</a>

    <!-- Laptop sidebar (right side in RTL) -->
    <aside
      class="sticky top-0 hidden h-dvh shrink-0 flex-col border-e border-line bg-card transition-[width] duration-200 lg:flex"
      :class="collapsed ? 'w-[76px]' : 'w-[248px]'"
      aria-label="القائمة الرئيسية"
    >
      <div class="flex h-16 items-center gap-3 px-4">
        <BrandMark :size="38" />
        <div v-if="!collapsed" class="min-w-0">
          <p class="truncate font-semibold leading-tight">{{ session.campName }}</p>
          <p class="text-[12.5px] text-muted">{{ session.isManager ? 'المدير' : 'عضو' }}</p>
        </div>
      </div>
      <nav class="mt-2 flex-1 space-y-1 px-3">
        <RouterLink
          v-for="item in nav"
          :key="item.to"
          :to="item.to"
          class="flex h-11 items-center gap-3 rounded-[10px] px-3 transition-colors"
          :class="isActive(item) ? 'bg-sage-soft font-semibold text-forest' : 'text-muted hover:bg-sunken hover:text-ink'"
          :aria-current="isActive(item) ? 'page' : undefined"
          :title="collapsed ? item.label : undefined"
        >
          <component :is="item.icon" class="size-5 shrink-0" :stroke-width="isActive(item) ? 2.2 : 1.8" />
          <span v-if="!collapsed">{{ item.label }}</span>
        </RouterLink>
      </nav>
      <div class="space-y-1 border-t border-line p-3">
        <RouterLink
          to="/settings"
          class="flex h-11 items-center gap-3 rounded-[10px] px-3"
          :class="route.name === 'settings' ? 'bg-sage-soft font-semibold text-forest' : 'text-muted hover:bg-sunken hover:text-ink'"
          :title="collapsed ? 'الإعدادات' : undefined"
        >
          <Settings class="size-5 shrink-0" />
          <span v-if="!collapsed">الإعدادات</span>
        </RouterLink>
        <button type="button" class="flex h-11 w-full items-center gap-3 rounded-[10px] px-3 text-muted hover:bg-sunken hover:text-ink" :aria-label="collapsed ? 'توسيع القائمة' : 'تصغير القائمة'" @click="toggleSidebar">
          <ChevronsLeft v-if="collapsed" class="size-5 shrink-0" />
          <ChevronsRight v-else class="size-5 shrink-0" />
          <span v-if="!collapsed">تصغير القائمة</span>
        </button>
      </div>
    </aside>

    <div class="min-w-0 flex-1">
      <!-- Top bar -->
      <header class="safe-top sticky top-0 z-30 border-b border-line bg-bg/90 backdrop-blur">
        <div class="mx-auto flex h-14 max-w-[1200px] items-center gap-2 px-4 lg:h-16 lg:px-8">
          <BrandMark :size="30" class="lg:hidden" />
          <div class="min-w-0 flex-1">
            <h1 class="truncate text-[17px] font-semibold lg:hidden">{{ title }}</h1>
            <p class="hidden text-[14.5px] text-muted lg:block">{{ formatDate(today, { weekday: true, year: true }) }}</p>
          </div>
          <button
            type="button"
            class="grid size-10 place-items-center rounded-full text-muted hover:bg-sunken hover:text-ink"
            :aria-label="ui.hideAmounts ? 'إظهار المبالغ' : 'إخفاء المبالغ'"
            :title="ui.hideAmounts ? 'إظهار المبالغ' : 'إخفاء المبالغ'"
            @click="ui.toggleAmounts()"
          >
            <EyeOff v-if="ui.hideAmounts" class="size-5" />
            <Eye v-else class="size-5" />
          </button>
          <RouterLink to="/notifications" class="relative grid size-10 place-items-center rounded-full text-muted hover:bg-sunken hover:text-ink" :aria-label="`الإشعارات${notifications.unread ? ` (${notifications.unread} جديدة)` : ''}`">
            <Bell class="size-5" />
            <span v-if="notifications.unread" class="num absolute end-1 top-1 grid min-w-[18px] place-items-center rounded-full bg-brass px-1 text-[11px] font-semibold leading-[18px] text-white">
              {{ notifications.unread > 99 ? '99+' : notifications.unread }}
            </span>
          </RouterLink>
          <UMenu :items="quickItems" label="تسجيل سريع" class="hidden lg:block" @select="openQuick">
            <template #trigger="{ toggle, open }">
              <button
                type="button"
                class="flex h-10 items-center gap-2 rounded-full bg-primary px-4 font-medium text-on-primary hover:bg-primary-hover"
                aria-haspopup="menu"
                :aria-expanded="open"
                @click.stop="toggle"
              >
                <Plus class="size-[18px]" /> تسجيل
              </button>
            </template>
          </UMenu>
          <div class="flex items-center">
            <UAvatar :name="session.user.name" :color="session.user.color" class="hidden lg:grid" />
            <UMenu :items="profileItems" label="الحساب" @select="onProfile" />
          </div>
        </div>
      </header>

      <main id="main" class="mx-auto max-w-[1200px] px-4 pb-32 pt-5 lg:px-8 lg:pb-16 lg:pt-7">
        <slot />
      </main>
    </div>

    <!-- Phone: floating add + bottom navigation -->
    <button
      type="button"
      class="fixed bottom-[calc(4.75rem+env(safe-area-inset-bottom))] end-4 z-30 grid size-14 place-items-center rounded-full bg-primary text-on-primary shadow-lg lg:hidden"
      aria-label="تسجيل سريع"
      @click="quickSheet = true"
    >
      <Plus class="size-6" />
    </button>
    <nav class="safe-bottom fixed inset-x-0 bottom-0 z-30 border-t border-line bg-card lg:hidden" aria-label="التنقل">
      <div class="mx-auto grid h-16 max-w-lg grid-cols-5">
        <RouterLink
          v-for="item in nav"
          :key="item.to"
          :to="item.to"
          class="flex flex-col items-center justify-center gap-0.5 text-[11.5px]"
          :class="isActive(item) ? 'font-semibold text-forest' : 'text-muted'"
          :aria-current="isActive(item) ? 'page' : undefined"
        >
          <span class="grid h-7 w-12 place-items-center rounded-full" :class="isActive(item) ? 'bg-sage-soft' : ''">
            <component :is="item.icon" class="size-5" :stroke-width="isActive(item) ? 2.2 : 1.8" />
          </span>
          {{ item.label }}
        </RouterLink>
      </div>
    </nav>

    <UDialog :open="quickSheet" title="تسجيل سريع" @close="quickSheet = false">
      <div class="grid grid-cols-2 gap-2 pb-2">
        <button
          v-for="item in quickItems"
          :key="item.key"
          type="button"
          class="flex h-16 items-center gap-3 rounded-[12px] border border-line px-4 text-start hover:bg-sunken"
          @click="openQuick(item.key)"
        >
          <component :is="item.icon" class="size-5 text-sage" />
          <span class="font-medium">{{ item.label }}</span>
        </button>
      </div>
    </UDialog>

    <QuickAddHost />
  </div>
</template>
