import { createRouter, createWebHistory } from 'vue-router';
import { useSession } from './stores/session.js';

const routes = [
  { path: '/login', name: 'login', component: () => import('./views/LoginView.vue'), meta: { public: true, title: 'تسجيل الدخول' } },
  { path: '/setup', name: 'setup', component: () => import('./views/SetupView.vue'), meta: { public: true, title: 'إعداد المعسكر' } },
  { path: '/password', name: 'password', component: () => import('./views/ChangePasswordView.vue'), meta: { bare: true, title: 'كلمة مرور جديدة' } },
  { path: '/', name: 'home', component: () => import('./views/HomeView.vue'), meta: { title: 'الرئيسية' } },
  { path: '/housing', name: 'housing', component: () => import('./views/HousingView.vue'), meta: { title: 'السكن' } },
  { path: '/work', name: 'work', component: () => import('./views/WorkView.vue'), meta: { title: 'العمل' } },
  { path: '/money', name: 'money', component: () => import('./views/MoneyView.vue'), meta: { title: 'المال' } },
  { path: '/me', name: 'me', component: () => import('./views/MeView.vue'), meta: { title: 'أنا' } },
  { path: '/task/:id', name: 'task', component: () => import('./views/TaskView.vue'), meta: { title: 'المهمة' } },
  { path: '/notifications', name: 'notifications', component: () => import('./views/NotificationsView.vue'), meta: { title: 'الإشعارات' } },
  { path: '/settings', name: 'settings', component: () => import('./views/SettingsView.vue'), meta: { title: 'الإعدادات' } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: (to, from, saved) => saved || (to.path !== from.path ? { top: 0 } : undefined),
});

router.beforeEach(async (to) => {
  const session = useSession();
  if (!session.loaded) {
    try {
      await session.load();
    } catch {
      // offline on first load: let public pages render, others show the shell's retry
    }
  }
  if (session.needsSetup && to.name !== 'setup') return { name: 'setup' };
  if (!session.needsSetup && to.name === 'setup') return { name: 'login' };
  if (!session.user && !to.meta.public) return { name: 'login', query: to.fullPath !== '/' ? { next: to.fullPath } : undefined };
  if (session.user && to.meta.public) return { name: 'home' };
  if (session.user?.mustChangePassword && to.name !== 'password') return { name: 'password' };
  return true;
});

router.afterEach((to) => {
  const session = useSession();
  document.title = to.meta.title ? `${to.meta.title} · ${session.campName}` : session.campName;
});
