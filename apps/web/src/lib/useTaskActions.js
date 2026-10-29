import { reactive } from 'vue';
import { useRouter } from 'vue-router';
import { ArrowLeftRight, CircleCheck, Play, RotateCcw, ThumbsUp, Undo2 } from 'lucide-vue-next';
import { del, post } from './api.js';
import { actions } from './actions.js';
import { useSession } from '../stores/session.js';
import { useUi } from '../stores/ui.js';

/** Everything a list needs to act on tasks, with the same permissions as the API. */
export function useTaskActions(onChange = () => {}) {
  const session = useSession();
  const ui = useUi();
  const router = useRouter();
  const dialogs = reactive({ edit: null, returnTask: null, swapTaskId: null, swapOpen: false });

  const me = () => session.user?.id;
  const canEdit = (t) => (t.kind === 'personal' ? t.assigneeId === me() : session.isManager);
  const isAssignee = (t) => t.assigneeId === me();
  const isApprover = (t) => (t.kind === 'personal' ? isAssignee(t) : session.isManager);

  function items(t) {
    const extra = [];
    const open = ['pending', 'in_progress', 'returned'].includes(t.status);
    if (isAssignee(t) && ['pending', 'returned'].includes(t.status) && t.kind !== 'personal') extra.push({ key: 'start', label: 'بدء العمل', icon: Play });
    if ((isAssignee(t) || isApprover(t)) && open) extra.push({ key: 'submit', label: 'أنجزت', icon: CircleCheck });
    if (isApprover(t) && t.status === 'submitted') {
      extra.push({ key: 'approve', label: 'اعتماد', icon: ThumbsUp });
      extra.push({ key: 'return', label: 'إعادة بملاحظة', icon: RotateCcw });
    }
    if ((isAssignee(t) || isApprover(t)) && (t.status === 'submitted' || (t.status === 'approved' && (!t.needsApproval || isApprover(t))))) {
      extra.push({ key: 'undo', label: 'تراجع عن الإنجاز', icon: Undo2 });
    }
    if (isAssignee(t) && t.kind !== 'personal' && open) extra.push({ key: 'swap', label: 'طلب تبديل', icon: ArrowLeftRight });
    const keys = ['view'];
    if (canEdit(t)) keys.push('edit', 'copy', t.archivedAt ? 'unarchive' : 'archive', 'delete');
    return actions(keys, extra);
  }

  async function act(t, action, extraBody = {}) {
    try {
      const r = await post(`/tasks/${t.id}/action`, { action, ...extraBody });
      const msg = {
        start: 'بدأت العمل على المهمة',
        submit: r.task.status === 'submitted' ? 'أُرسلت للاعتماد' : 'أحسنت! أُنجزت المهمة',
        approve: 'اعتُمدت المهمة',
        return: 'أُعيدت المهمة مع ملاحظتك',
        undo: 'أُعيدت المهمة لقيد العمل',
        set: 'تغيّرت حالة المهمة',
      }[action];
      ui.toast(r.nextTaskId ? `${msg} · أُضيفت المرة القادمة` : msg);
      ui.bump('tasks', 'housing');
      onChange(r.task);
      return r.task;
    } catch (e) {
      ui.error(e);
      return null;
    }
  }

  async function run(t, key) {
    switch (key) {
      case 'view':
        return router.push(`/task/${t.id}`);
      case 'edit':
        dialogs.edit = t;
        return null;
      case 'copy':
        try {
          await post(`/tasks/${t.id}/copy`);
          ui.toast('نُسخت المهمة');
          ui.bump('tasks', 'housing');
          onChange();
        } catch (e) {
          ui.error(e);
        }
        return null;
      case 'archive':
      case 'unarchive':
        try {
          await post(`/tasks/${t.id}/${key}`);
          ui.toast(key === 'archive' ? 'أُرشفت المهمة' : 'أُعيدت من الأرشيف');
          ui.bump('tasks', 'housing');
          onChange();
        } catch (e) {
          ui.error(e);
        }
        return null;
      case 'delete': {
        const ok = await ui.confirm({
          title: 'حذف المهمة؟',
          body: t.kind !== 'personal' && t.assigneeId && t.assigneeId !== me() ? `سيصل إشعار بالحذف إلى ${t.assigneeName}.` : 'يمكنك استعادتها خلال 30 يوماً من المحذوفات.',
          confirmLabel: 'حذف',
          danger: true,
        });
        if (!ok) return null;
        await ui.deleteWithUndo({
          remove: () => del(`/tasks/${t.id}`),
          restore: () => post(`/tasks/${t.id}/restore`),
          message: 'حُذفت المهمة',
          after: () => {
            ui.bump('tasks', 'housing');
            onChange();
          },
        });
        return null;
      }
      case 'return':
        dialogs.returnTask = t;
        return null;
      case 'swap':
        dialogs.swapTaskId = t.id;
        dialogs.swapOpen = true;
        return null;
      default:
        return act(t, key);
    }
  }

  /** Round check: done ⇄ not done. */
  function toggle(t) {
    if (t.status === 'approved' || t.status === 'submitted') return act(t, 'undo');
    return act(t, 'submit');
  }

  return { items, run, act, toggle, dialogs, canEdit, isAssignee, isApprover };
}
