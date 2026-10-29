import { defineStore } from 'pinia';
import { ApiError, get, post } from '../lib/api.js';

export const useSession = defineStore('session', {
  state: () => ({
    user: null,
    campName: 'معسكر نقلة',
    members: [],
    specialties: {},
    loaded: false,
    needsSetup: false,
  }),
  getters: {
    isManager: (s) => s.user?.role === 'manager',
    activeMembers: (s) => s.members.filter((m) => !m.archivedAt),
    memberName: (s) => (id) => s.members.find((m) => m.id === id)?.name || '—',
    member: (s) => (id) => s.members.find((m) => m.id === id) || null,
    settings: (s) => s.user?.settings || {},
  },
  actions: {
    async load() {
      try {
        const r = await get('/auth/me');
        this.user = r.user;
        this.campName = r.campName;
        await this.loadMembers();
        this.needsSetup = false;
      } catch (e) {
        this.user = null;
        if (e instanceof ApiError && e.status === 401) {
          const s = await get('/setup/status').catch(() => ({ needsSetup: false }));
          this.needsSetup = s.needsSetup;
          if (s.campName) this.campName = s.campName;
        } else if (!(e instanceof ApiError) || e.status === 0) {
          throw e;
        }
      } finally {
        this.loaded = true;
      }
      this.applyTheme();
    },
    async loadMembers() {
      const r = await get('/members');
      this.members = r.members;
      this.specialties = r.specialties;
    },
    async login(username, password, remember) {
      const r = await post('/auth/login', { username, password, remember });
      this.user = r.user;
      await this.load();
    },
    async setup(payload) {
      const r = await post('/setup', payload);
      this.user = r.user;
      await this.load();
    },
    async logout() {
      try {
        await post('/auth/logout');
      } finally {
        this.user = null;
        this.members = [];
      }
    },
    setUser(user) {
      this.user = user;
      this.applyTheme();
    },
    applyTheme() {
      const theme = this.user?.settings?.theme || localStorage.getItem('camp-theme') || 'system';
      try {
        localStorage.setItem('camp-theme', theme);
      } catch {
        /* private mode */
      }
      const dark = theme === 'dark' || (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
      document.documentElement.classList.toggle('dark', dark);
      document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#121715' : '#243F35');
    },
  },
});
