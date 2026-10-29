import { defineStore } from 'pinia';
import { del, get, post } from '../lib/api.js';

export const useNotifications = defineStore('notifications', {
  state: () => ({ items: [], unread: 0, types: {}, loading: false, timer: null }),
  actions: {
    async load() {
      this.loading = true;
      try {
        const r = await get('/notifications', { limit: 60 });
        this.items = r.notifications;
        this.unread = r.unread;
        this.types = r.types;
      } catch {
        /* the bell stays as it was */
      } finally {
        this.loading = false;
      }
    },
    start() {
      this.stop();
      this.load();
      this.timer = setInterval(() => document.visibilityState === 'visible' && this.load(), 60000);
    },
    stop() {
      if (this.timer) clearInterval(this.timer);
      this.timer = null;
    },
    async markRead(n) {
      if (n.readAt) return;
      n.readAt = new Date().toISOString();
      this.unread = Math.max(0, this.unread - 1);
      await post(`/notifications/${n.id}/read`).catch(() => {});
    },
    async markAll() {
      this.items.forEach((n) => (n.readAt = n.readAt || new Date().toISOString()));
      this.unread = 0;
      await post('/notifications/read-all').catch(() => {});
    },
    async remove(n) {
      await del(`/notifications/${n.id}`);
      this.items = this.items.filter((x) => x.id !== n.id);
      if (!n.readAt) this.unread = Math.max(0, this.unread - 1);
    },
    async restore(n) {
      await post(`/notifications/${n.id}/restore`);
      await this.load();
    },
  },
});
