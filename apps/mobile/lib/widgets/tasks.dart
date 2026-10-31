import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

class TaskAction {
  const TaskAction(this.key, this.label, this.icon, {this.danger = false});
  final String key;
  final String label;
  final IconData icon;
  final bool danger;
}

/// Same permissions as the API (apps/web/src/lib/useTaskActions.js).
class TaskActions {
  TaskActions(this.context);
  final BuildContext context;

  Session get _session => context.read<Session>();
  Api get _api => _session.api;
  int? get _me => _session.user?.id;

  bool isAssignee(Task t) => t.assigneeId == _me;
  bool isApprover(Task t) => t.kind == 'personal' ? isAssignee(t) : _session.isManager;
  bool canEdit(Task t) => t.kind == 'personal' ? isAssignee(t) : _session.isManager;

  List<TaskAction> workflow(Task t) {
    final list = <TaskAction>[];
    final open = t.isOpen;
    if (isAssignee(t) && (t.status == 'pending' || t.status == 'returned') && t.kind != 'personal') {
      list.add(const TaskAction('start', 'بدء العمل', Icons.play_arrow_rounded));
    }
    if ((isAssignee(t) || isApprover(t)) && open) list.add(const TaskAction('submit', 'أنجزت', Icons.check_circle_outline_rounded));
    if (isApprover(t) && t.status == 'submitted') {
      list.add(const TaskAction('approve', 'اعتماد', Icons.thumb_up_alt_outlined));
      list.add(const TaskAction('return', 'إعادة بملاحظة', Icons.replay_rounded));
    }
    if ((isAssignee(t) || isApprover(t)) && (t.status == 'submitted' || (t.status == 'approved' && (!t.needsApproval || isApprover(t))))) {
      list.add(const TaskAction('undo', 'تراجع عن الإنجاز', Icons.undo_rounded));
    }
    return list;
  }

  List<TaskAction> manage(Task t) {
    if (!canEdit(t)) return const [];
    return [
      const TaskAction('copy', 'نسخ', Icons.copy_rounded),
      t.archived ? const TaskAction('unarchive', 'إلغاء الأرشفة', Icons.unarchive_outlined) : const TaskAction('archive', 'أرشفة', Icons.archive_outlined),
      const TaskAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ];
  }

  void _done() => context.read<RefreshBus>().bump();

  /// Runs an action. Returns the updated task map when the server sent one.
  Future<Map<String, dynamic>?> run(Task t, String key) async {
    try {
      switch (key) {
        case 'copy':
          await _api.post('/tasks/${t.id}/copy');
          if (context.mounted) toast(context, 'نُسخت المهمة');
          _done();
          return null;
        case 'archive':
        case 'unarchive':
          await _api.post('/tasks/${t.id}/$key');
          if (context.mounted) toast(context, key == 'archive' ? 'أُرشفت المهمة' : 'أُعيدت من الأرشيف');
          _done();
          return null;
        case 'delete':
          final ok = await confirmDialog(
            context,
            title: 'حذف المهمة؟',
            body: t.kind != 'personal' && t.assigneeId != null && t.assigneeId != _me
                ? 'سيصل إشعار بالحذف إلى ${t.assigneeName ?? 'المكلَّف'}.'
                : 'يمكنك استعادتها خلال 30 يوماً من المحذوفات.',
            confirmLabel: 'حذف',
            danger: true,
          );
          if (!ok) return null;
          final res = await _api.delete('/tasks/${t.id}');
          _done();
          if (res['result'] == 'archived') {
            if (context.mounted) toast(context, 'المهمة منجزة، فأُرشفت بدل حذفها');
            return {'deleted': true};
          }
          if (context.mounted) {
            final messenger = ScaffoldMessenger.of(context);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: const Text('حُذفت المهمة'),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'تراجع',
                  onPressed: () async {
                    try {
                      await _api.post('/tasks/${t.id}/restore');
                      _done();
                    } catch (_) {
                      // the snackbar is gone; nothing else to show
                    }
                  },
                ),
              ));
          }
          return {'deleted': true};
        case 'return':
          final note = await promptText(context, title: 'إعادة المهمة', label: 'ما الذي يحتاج تعديلاً؟', hint: t.title, confirmLabel: 'إعادة مع الملاحظة');
          if (note == null) return null;
          return act(t, 'return', {'note': note});
        default:
          return act(t, key, const {});
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> act(Task t, String action, Map<String, dynamic> extra) async {
    final Map<String, dynamic> r;
    try {
      r = await _api.post('/tasks/${t.id}/action', {'action': action, ...extra});
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
      return null;
    }
    final task = r['task'] is Map<String, dynamic> ? r['task'] as Map<String, dynamic> : null;
    final status = task?['status'];
    final msg = switch (action) {
      'start' => 'بدأت العمل على المهمة',
      'submit' => status == 'submitted' ? 'أُرسلت للاعتماد' : 'أحسنت! أُنجزت المهمة',
      'approve' => 'اعتُمدت المهمة',
      'return' => 'أُعيدت المهمة مع ملاحظتك',
      'undo' => 'أُعيدت المهمة لقيد العمل',
      _ => 'تغيّرت حالة المهمة',
    };
    if (context.mounted) toast(context, r['nextTaskId'] != null ? '$msg · أُضيفت المرة القادمة' : msg);
    _done();
    return task;
  }

  /// Round check: done ⇄ not done.
  Future<void> toggle(Task t) async {
    if (t.status == 'approved' || t.status == 'submitted') {
      await run(t, 'undo');
    } else {
      await run(t, 'submit');
    }
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.task, {super.key, this.overdue = false});
  final Task task;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (overdue) return Pill('متأخرة', fg: c.danger, bg: c.dangerSoft);
    return switch (task.status) {
      'approved' => Pill('منجزة', fg: c.sage, bg: c.sageSoft),
      'submitted' => Pill('بانتظار الاعتماد', fg: c.brass, bg: c.brassSoft),
      'returned' => Pill('مُعادة', fg: c.danger, bg: c.dangerSoft),
      'in_progress' => Pill('قيد العمل', fg: c.forest, bg: c.sageSoft),
      _ => Pill('قيد الانتظار', fg: c.muted, bg: c.sunken),
    };
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow(this.task, {super.key, this.showAssignee = false, this.today, this.nowTime});

  final Task task;
  final bool showAssignee;
  final String? today;
  final String? nowTime;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = task;
    final ta = TaskActions(context);
    final overdue = t.isOverdue(today ?? adenDate(), nowTime ?? adenTime());
    final canCheck = (ta.isAssignee(t) || ta.isApprover(t)) && (t.isOpen || t.status == 'submitted' || t.status == 'approved');
    final meta = <String>[
      kindLabels[t.kind] ?? '',
      if (t.projectName != null) t.projectName!,
      if (t.dueDate != null) '${relativeDay(t.dueDate)}${t.dueTime != null ? ' ${formatTime(t.dueTime)}' : ''}',
      if (t.kind == 'house') count(t.size, pointsForms),
      if (t.kind == 'company') count(t.size, hoursForms),
    ];
    return InkWell(
      onTap: () => context.push('/task/${t.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Check(task: t, enabled: canCheck, onTap: () => ta.toggle(t)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.isDone ? c.muted : c.ink,
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(meta.where((s) => s.isNotEmpty).join(' · '), style: TextStyle(fontSize: 12.5, color: overdue ? c.danger : c.muted)),
                  if (t.priority == 'urgent' || t.priority == 'high' || t.status != 'pending' || overdue) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (t.status != 'pending' || overdue) StatusPill(t, overdue: overdue && t.isOpen),
                      if (t.priority == 'urgent') Pill('عاجلة', fg: c.danger, bg: c.dangerSoft, icon: Icons.flag_rounded),
                      if (t.priority == 'high') Pill('مهمة', fg: c.brass, bg: c.brassSoft, icon: Icons.flag_outlined),
                    ]),
                  ],
                ],
              ),
            ),
            if (showAssignee && t.assigneeId != null) ...[
              const SizedBox(width: 8),
              Avatar(name: t.assigneeName ?? '', color: t.assigneeColor, size: 28),
            ],
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.task, required this.enabled, required this.onTap});
  final Task task;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = task.isDone;
    final waiting = task.status == 'submitted';
    return Semantics(
      button: true,
      label: done ? 'إلغاء الإنجاز' : 'تعليم كمنجزة',
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 24,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? c.sage : (waiting ? c.brassSoft : Colors.transparent),
            border: Border.all(color: done ? c.sage : (waiting ? c.brass : c.line), width: 2),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : (waiting ? Icon(Icons.hourglass_top_rounded, size: 15, color: c.brass) : null),
        ),
      ),
    );
  }
}

/// A list of task rows inside a card, with dividers.
class TaskList extends StatelessWidget {
  const TaskList(this.tasks, {super.key, this.showAssignee = false, this.today, this.nowTime});
  final List<Task> tasks;
  final bool showAssignee;
  final String? today;
  final String? nowTime;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            TaskRow(tasks[i], showAssignee: showAssignee, today: today, nowTime: nowTime),
          ],
        ],
      ),
    );
  }
}
