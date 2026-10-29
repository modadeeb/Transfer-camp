// Task lifecycle (docs/Muaskar-spec.md §8-ج).
import { addDays } from './dates.js';

export const TASK_KINDS = ['house', 'company', 'personal'];
export const TASK_STATUSES = ['pending', 'in_progress', 'submitted', 'approved', 'returned'];
export const PRIORITIES = ['normal', 'high', 'urgent'];
export const RECURRENCES = ['none', 'daily', 'weekly'];

export const STATUS_LABELS = {
  pending: 'قيد الانتظار',
  in_progress: 'قيد العمل',
  submitted: 'بانتظار الاعتماد',
  approved: 'منجزة',
  returned: 'مُعادة',
};
export const PRIORITY_LABELS = { normal: 'عادية', high: 'مهمة', urgent: 'عاجلة' };
export const KIND_LABELS = { house: 'سكن', company: 'شركة', personal: 'شخصية' };

export class TransitionError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TransitionError';
  }
}

/**
 * Next status for an action. Throws TransitionError when not allowed.
 * @param {{status:string, needsApproval:boolean|number}} task
 * @param {'start'|'submit'|'approve'|'return'|'undo'|'set'} action
 * @param {{isManager:boolean, isAssignee:boolean, status?:string}} ctx
 */
export function nextStatus(task, action, { isManager = false, isAssignee = false, status } = {}) {
  const from = task.status;
  const needsApproval = Boolean(task.needsApproval);
  switch (action) {
    case 'start':
      if (!isAssignee) throw new TransitionError('هذه المهمة ليست مسندة إليك');
      if (!['pending', 'returned'].includes(from)) throw new TransitionError('لا يمكن بدء المهمة في حالتها الحالية');
      return 'in_progress';
    case 'submit':
      if (!isAssignee && !isManager) throw new TransitionError('هذه المهمة ليست مسندة إليك');
      if (!['pending', 'in_progress', 'returned'].includes(from)) throw new TransitionError('المهمة منجزة أو بانتظار الاعتماد');
      return needsApproval && !isManager ? 'submitted' : 'approved';
    case 'approve':
      if (!isManager) throw new TransitionError('الاعتماد للمدير فقط');
      if (from !== 'submitted') throw new TransitionError('المهمة ليست بانتظار الاعتماد');
      return 'approved';
    case 'return':
      if (!isManager) throw new TransitionError('الإعادة للمدير فقط');
      if (!['submitted', 'approved'].includes(from)) throw new TransitionError('لا يمكن إعادة مهمة لم تُنجز');
      return 'returned';
    case 'undo':
      if (!isAssignee && !isManager) throw new TransitionError('هذه المهمة ليست مسندة إليك');
      if (from === 'submitted') return 'in_progress';
      if (from === 'approved' && (!needsApproval || isManager)) return 'in_progress';
      throw new TransitionError('لا يمكن التراجع عن هذه المهمة');
    case 'set':
      if (!isManager) throw new TransitionError('تغيير الحالة للمدير فقط');
      if (!TASK_STATUSES.includes(status)) throw new TransitionError('حالة غير معروفة');
      return status;
    default:
      throw new TransitionError('إجراء غير معروف');
  }
}

export function isOverdue(task, today, nowTime = '00:00') {
  if (!task.dueDate || task.status === 'approved') return false;
  if (task.dueDate < today) return true;
  return task.dueDate === today && Boolean(task.dueTime) && task.dueTime < nowTime;
}

export function nextOccurrence(date, recurrence) {
  if (recurrence === 'daily') return addDays(date, 1);
  if (recurrence === 'weekly') return addDays(date, 7);
  return null;
}

/** Default approval rule: company tasks need approval, house/personal don't. */
export function defaultNeedsApproval(kind) {
  return kind === 'company';
}
