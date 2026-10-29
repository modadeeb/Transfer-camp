import { post } from './api.js';
import { useUi } from '../stores/ui.js';

/** ▲▼ arrows: swap neighbours locally, then save the new order of the visible list. */
export function useReorder(entity, listRef, onFail = () => {}) {
  const ui = useUi();
  async function move(index, delta) {
    const list = [...listRef.value];
    const target = index + delta;
    if (target < 0 || target >= list.length) return;
    [list[index], list[target]] = [list[target], list[index]];
    listRef.value = list;
    try {
      await post('/reorder', { entity, ids: list.map((x) => x.id) });
    } catch (e) {
      ui.error(e);
      onFail();
    }
  }
  return { up: (i) => move(i, -1), down: (i) => move(i, 1) };
}
