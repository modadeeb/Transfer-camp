import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/tasks.dart';
import 'task_form_screen.dart';

const _historyLabels = {
  'created': 'أُنشئت',
  'updated': 'عُدّلت',
  'start': 'بدأ العمل',
  'submit': 'أُنجزت',
  'approve': 'اعتُمدت',
  'return': 'أُعيدت',
  'undo': 'تراجع عن الإنجاز',
  'set': 'تغيّرت الحالة',
  'deleted': 'حُذفت',
  'restored': 'استُعيدت',
  'archived': 'أُرشفت',
  'unarchived': 'أُعيدت من الأرشيف',
  'swapped': 'نُقلت بالتبديل',
};

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'تعذّر فتح الرابط', error: true);
  }
}

class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    return Scaffold(
      appBar: AppBar(title: const Text('المهمة')),
      body: Loader(
        load: () => api.get('/tasks/$id'),
        builder: (context, data, reload) => _TaskBody(data: data, reload: reload),
      ),
    );
  }
}

class _TaskBody extends StatefulWidget {
  const _TaskBody({required this.data, required this.reload});
  final Map<String, dynamic> data;
  final Future<void> Function() reload;

  @override
  State<_TaskBody> createState() => _TaskBodyState();
}

class _TaskBodyState extends State<_TaskBody> {
  final _note = TextEditingController();
  final _url = TextEditingController();
  String? _acting;

  @override
  void dispose() {
    _note.dispose();
    _url.dispose();
    super.dispose();
  }

  Task get t => Task(widget.data['task'] as Map<String, dynamic>);

  Future<void> _act(String key) async {
    final ta = TaskActions(context);
    setState(() => _acting = key);
    if (key == 'submit') {
      var url = _url.text.trim();
      if (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
      final r = await ta.act(t, 'submit', {'note': _note.text.trim().isEmpty ? null : _note.text.trim(), if (url.isNotEmpty) 'url': url});
      if (r != null) {
        _note.clear();
        _url.clear();
      }
    } else {
      final r = await ta.run(t, key);
      if (r?['deleted'] == true && mounted) {
        Navigator.of(context).maybePop();
        return;
      }
    }
    if (mounted) setState(() => _acting = null);
  }

  Future<void> _manage(String key) async {
    if (key == 'edit') {
      await TaskFormScreen.open(context, task: t);
      return;
    }
    await _act(key);
  }

  Future<void> _toggleItem(ChecklistItem item) async {
    try {
      await context.read<Session>().api.post('/tasks/${t.id}/checklist', {'itemId': item.id, 'done': !item.done});
      await widget.reload();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = context.read<Session>();
    final task = t;
    final ta = TaskActions(context);
    final workflow = ta.workflow(task);
    final manage = ta.manage(task);
    final history = (widget.data['history'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    final overdue = task.isOverdue(adenDate(), adenTime()) && task.isOpen;
    final canSubmit = workflow.any((a) => a.key == 'submit');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${kindLabels[task.kind]}${task.projectName != null ? ' · ${task.projectName}' : ''}', style: TextStyle(color: c.muted, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(task.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    StatusPill(task, overdue: overdue),
                    if (manage.isNotEmpty || ta.canEdit(task))
                      PopupMenuButton<String>(
                        tooltip: 'إجراءات',
                        onSelected: _manage,
                        itemBuilder: (_) => [
                          if (ta.canEdit(task)) const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
                          for (final a in manage)
                            PopupMenuItem(
                              value: a.key,
                              child: ListTile(
                                leading: Icon(a.icon, color: a.danger ? c.danger : null),
                                title: Text(a.label, style: TextStyle(color: a.danger ? c.danger : null)),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    _Meta('المكلَّف', task.assigneeId == null ? 'غير مُسنَدة' : session.memberName(task.assigneeId), leading: task.assigneeId == null ? null : Avatar(name: task.assigneeName ?? '', color: task.assigneeColor, size: 22)),
                    _Meta('الموعد', task.dueDate == null ? 'بلا موعد' : '${formatDate(task.dueDate, weekday: true)}${task.dueTime != null ? ' ${formatTime(task.dueTime)}' : ''}', danger: overdue),
                    _Meta('الأولوية', priorityLabels[task.priority] ?? ''),
                    if (task.kind == 'house') _Meta('النقاط', '${task.size}'),
                    if (task.kind == 'company') _Meta('الساعات', '${task.size}'),
                    if (task.specialty != null) _Meta('التخصص', specialtyLabels[task.specialty] ?? task.specialty!),
                    if (task.recurrence != 'none') _Meta('التكرار', task.recurrence == 'daily' ? 'يومياً' : 'أسبوعياً'),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (task.status == 'returned' && (task.returnNote ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.brassSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.brass.withAlpha(90))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ملاحظة المدير', style: TextStyle(color: c.brass, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(task.returnNote!),
              ],
            ),
          ),
        ],
        if ((task.details ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(title: 'التفاصيل', child: SelectableText(task.details!)),
        ],
        if (task.checklist.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'قائمة التحقق',
            subtitle: '${task.checklist.where((i) => i.done).length} من ${task.checklist.length}',
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              children: [
                for (final item in task.checklist)
                  CheckboxListTile(
                    value: item.done,
                    onChanged: (ta.isAssignee(task) || ta.canEdit(task)) ? (_) => _toggleItem(item) : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(item.text, style: TextStyle(decoration: item.done ? TextDecoration.lineThrough : null, color: item.done ? c.muted : null)),
                  ),
              ],
            ),
          ),
        ],
        if (task.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'روابط ومرفقات',
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              children: [
                for (final a in task.attachments)
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: Text(a.label ?? a.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => openLink(context, a.url),
                  ),
              ],
            ),
          ),
        ],
        if ((task.completionNote ?? '').isNotEmpty || (task.completionUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'ما أُنجز',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((task.completionNote ?? '').isNotEmpty) SelectableText(task.completionNote!),
                if ((task.completionUrl ?? '').isNotEmpty)
                  TextButton.icon(onPressed: () => openLink(context, task.completionUrl!), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('رابط العمل')),
              ],
            ),
          ),
        ],
        if (workflow.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'إنجاز المهمة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canSubmit && task.kind != 'personal') ...[
                  TextField(controller: _note, minLines: 2, maxLines: 5, maxLength: 1000, decoration: const InputDecoration(labelText: 'ملاحظة عن الإنجاز (اختياري)')),
                  TextField(controller: _url, textDirection: TextDirection.ltr, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط العمل (اختياري)', hintText: 'https://')),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in workflow)
                      a.key == 'submit' || a.key == 'approve'
                          ? FilledButton.icon(onPressed: _acting != null ? null : () => _act(a.key), icon: Icon(a.icon, size: 20), label: Text(a.label))
                          : OutlinedButton.icon(onPressed: _acting != null ? null : () => _act(a.key), icon: Icon(a.icon, size: 20), label: Text(a.label)),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'السجل',
            child: Column(
              children: [
                for (final h in history)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 9, color: c.sage)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(TextSpan(children: [
                                TextSpan(text: '${h['actorName'] ?? ''} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: _historyLabels[h['action']] ?? '${h['action']}'),
                              ])),
                              Text(timeAgo('${h['createdAt']}'), style: TextStyle(color: c.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value, {this.leading, this.danger = false});
  final String label;
  final String value;
  final Widget? leading;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.muted, fontSize: 12.5)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? c.danger : null)),
        ]),
      ],
    );
  }
}
