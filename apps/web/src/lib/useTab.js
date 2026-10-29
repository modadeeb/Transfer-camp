import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';

/** Tab state kept in the URL (?tab=), so links and back button work. */
export function useTab(tabs, fallback) {
  const route = useRoute();
  const router = useRouter();
  return computed({
    get: () => {
      const keys = (typeof tabs === 'function' ? tabs() : tabs.value || tabs).map((t) => t.key);
      return keys.includes(route.query.tab) ? route.query.tab : fallback;
    },
    set: (tab) => router.replace({ query: { ...route.query, tab } }),
  });
}
