import { defineStore } from 'pinia';
import { ApiError } from '../lib/api.js';

let toastId = 0;

/**
 * Cross-view UI state: toasts (with undo), confirm dialog, the quick-add dialog,
 * amount hiding, and "data changed" counters views can watch to refresh.
 */
export const useUi = defineStore('ui', {
  state: () => ({
    toasts: [],
    confirmState: null,
    quickAdd: null, // 'task' | 'sharedExpense' | 'personalExpense' | 'swap' | 'absence' | null
    hideAmounts: localStorage.getItem('camp-hide-amounts') === '1',
    versions: { tasks: 0, money: 0, budget: 0, personal: 0, housing: 0, members: 0, notifications: 0 },
    isDesktop: window.matchMedia('(min-width: 1024px)').matches,
  }),
  actions: {
    toast(message, { type = 'success', action = null, duration = 4000 } = {}) {
      const id = ++toastId;
      this.toasts.push({ id, message, type, action });
      setTimeout(() => this.dismiss(id), action ? Math.max(duration, 5000) : duration);
      return id;
    },
    error(e) {
      const message = e instanceof ApiError || e?.message ? e.message : 'حدث خطأ غير متوقع';
      this.toast(message, { type: 'error', duration: 5000 });
    },
    dismiss(id) {
      this.toasts = this.toasts.filter((t) => t.id !== id);
    },
    confirm({ title, body = '', confirmLabel = 'تأكيد', danger = false }) {
      return new Promise((resolve) => {
        this.confirmState = { title, body, confirmLabel, danger, resolve };
      });
    },
    resolveConfirm(value) {
      this.confirmState?.resolve(value);
      this.confirmState = null;
    },
    toggleAmounts() {
      this.hideAmounts = !this.hideAmounts;
      localStorage.setItem('camp-hide-amounts', this.hideAmounts ? '1' : '0');
    },
    bump(...keys) {
      for (const k of keys) this.versions[k] = (this.versions[k] || 0) + 1;
    },
    /** Soft delete with a 5-second undo. */
    async deleteWithUndo({ remove, restore, message = 'حُذف', after }) {
      try {
        const r = await remove();
        const archived = r?.result === 'archived';
        after?.();
        this.toast(archived ? 'المهمة منجزة؛ أُرشفت بدلاً من حذفها لتبقى في رصيد العدالة' : message, {
          action: archived || !restore
            ? null
            : {
                label: 'تراجع',
                run: async () => {
                  await restore();
                  after?.();
                },
              },
        });
      } catch (e) {
        this.error(e);
      }
    },
  },
});
