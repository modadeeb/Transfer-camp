// The unified action set (spec §10): same icons, labels and order everywhere.
import { Archive, ArchiveRestore, Copy, Eye, Pencil, Trash2 } from 'lucide-vue-next';

export const ACTIONS = {
  view: { key: 'view', label: 'عرض', icon: Eye, primary: true },
  edit: { key: 'edit', label: 'تعديل', icon: Pencil, primary: true },
  copy: { key: 'copy', label: 'نسخ', icon: Copy },
  archive: { key: 'archive', label: 'أرشفة', icon: Archive },
  unarchive: { key: 'unarchive', label: 'إلغاء الأرشفة', icon: ArchiveRestore },
  delete: { key: 'delete', label: 'حذف', icon: Trash2, danger: true, primary: true },
};

/** Build an action list in the canonical order; extra (entity-specific) actions go before delete. */
export function actions(keys, extra = []) {
  const order = ['view', 'edit', 'copy', 'archive', 'unarchive'];
  const list = order.filter((k) => keys.includes(k)).map((k) => ACTIONS[k]);
  list.push(...extra.filter(Boolean));
  if (keys.includes('delete')) list.push(ACTIONS.delete);
  return list;
}
