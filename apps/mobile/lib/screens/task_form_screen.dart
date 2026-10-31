import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';

/// Create or edit a task. Same fields and rules as apps/web/src/components/forms/TaskForm.vue.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.task, this.kind});
  final Task? task;
  final String? kind;

  static Future<bool?> open(BuildContext context, {Task? task, String? kind}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => TaskFormScreen(task: task, kind: kind)));

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Session _session = context.read<Session>();
  late String _kind;
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _newItem = TextEditingController();
  final _linkUrl = TextEditingController();
  final _linkLabel = TextEditingController();
  Set<int> _assignees = {};
  int? _assignee;
  int? _projectId;
  String? _specialty;
  String? _dueDate;
  String? _dueTime;
  String _priority = 'normal';
  int _size = 2;
  String _recurrence = 'none';
  bool? _needsApproval;
  List<Map<String, dynamic>> _checklist = [];
  List<Map<String, dynamic>> _attachments = [];
  List<Map<String, dynamic>> _projects = [];
  bool _saving = false;
  bool _suggesting = false;
  bool _more = false;
  Map<String, String> _errors = {};

  bool get _editing => widget.task != null;
  bool get _shared => _kind != 'personal';
  bool get _approval => _needsApproval ?? _kind == 'company';

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _kind = t.kind;
      _title.text = t.title;
      _details.text = t.details ?? '';
      _assignee = t.assigneeId;
      _projectId = _int(t.raw['projectId']);
      _specialty = t.specialty;
      _dueDate = t.dueDate;
      _dueTime = t.dueTime;
      _priority = t.priority;
      _size = t.size.toInt();
      _recurrence = t.recurrence;
      _needsApproval = t.needsApproval;
      _checklist = t.checklist.map((i) => {'id': i.id, 'text': i.text, 'done': i.done}).toList();
      _attachments = t.attachments.map((a) => {'url': a.url, 'label': a.label}).toList();
      _more = (t.details ?? '').isNotEmpty || _checklist.isNotEmpty || _attachments.isNotEmpty || t.recurrence != 'none';
    } else {
      _kind = widget.kind ?? (_session.isManager ? 'house' : 'personal');
      if (!_session.isManager) _kind = 'personal';
      _dueDate = adenDate();
    }
    if (_session.isManager) _loadProjects();
  }

  int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

  Future<void> _loadProjects() async {
    try {
      final r = await _session.api.get('/projects');
      if (mounted) setState(() => _projects = (r['projects'] as List? ?? const []).whereType<Map<String, dynamic>>().where((p) => p['archivedAt'] == null).toList());
    } on ApiException {
      // projects are optional
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _details, _newItem, _linkUrl, _linkLabel]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final r = await _session.api.get('/tasks/suggest', {'kind': _kind, 'specialty': _specialty, 'date': _dueDate});
      final list = (r['suggestions'] as List? ?? const []).whereType<Map>().toList();
      final pick = list.isEmpty ? null : _int(list.first['userId']);
      if (!mounted) return;
      if (pick == null) {
        toast(context, 'لا يوجد أعضاء متاحون', error: true);
        return;
      }
      setState(() {
        if (_editing) {
          _assignee = pick;
        } else {
          _assignees = {pick};
        }
      });
      toast(context, 'الاقتراح: ${_session.memberName(pick)} (الأقل عبئاً)');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _save() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'details': _details.text.trim().isEmpty ? null : _details.text.trim(),
      'dueDate': _dueDate,
      'dueTime': _dueTime,
      'priority': _priority,
      'size': _size,
      'recurrence': _recurrence,
      'checklist': _checklist,
      'attachments': _attachments,
    };
    if (_shared) {
      body['needsApproval'] = _approval;
      if (_kind == 'company') {
        body['projectId'] = _projectId;
        body['specialty'] = _specialty;
      }
    }
    setState(() => _saving = true);
    try {
      Map<String, dynamic> r;
      if (_editing) {
        if (_shared) body['assigneeId'] = _assignee;
        r = await _session.api.patch('/tasks/${widget.task!.id}', body);
      } else {
        r = await _session.api.post('/tasks', {
          ...body,
          'kind': _kind,
          if (_shared) 'assigneeIds': _assignees.toList(),
          if (_shared) 'autoAssign': _assignees.isEmpty,
        });
      }
      if (!mounted) return;
      final n = (r['tasks'] as List?)?.length ?? 1;
      toast(context, _editing ? 'حُفظت التعديلات' : (n > 1 ? 'أُضيفت ${count(n, tasksForms)}' : 'أُضيفت المهمة'));
      context.read<RefreshBus>().bump();
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.fields);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final members = _session.members.where((m) => !m.archived).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'تعديل المهمة' : 'مهمة جديدة')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (!_editing && _session.isManager) ...[
              const FieldLabel('النوع'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'house', label: Text('سكن')),
                  ButtonSegment(value: 'company', label: Text('شركة')),
                  ButtonSegment(value: 'personal', label: Text('شخصية')),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  if (_kind == 'house' && _size > 5) _size = 3;
                }),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _title,
              maxLength: 140,
              decoration: InputDecoration(labelText: 'المهمة', hintText: 'مثال: تصميم شاشة الدخول', errorText: _errors['title']),
              validator: (v) => (v ?? '').trim().length < 2 ? 'اكتب عنوان المهمة' : null,
            ),
            if (_shared) ...[
              const SizedBox(height: 8),
              FieldLabel(_editing ? 'المكلَّف' : 'المكلَّفون', hint: !_editing && _assignees.isEmpty ? 'إن لم تختر أحداً، يُسنِدها النظام للأقل عبئاً' : null),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in members)
                    FilterChip(
                      avatar: Avatar(name: m.name, color: m.color, size: 22),
                      label: Text(m.name),
                      selected: _editing ? _assignee == m.id : _assignees.contains(m.id),
                      showCheckmark: false,
                      onSelected: (on) => setState(() {
                        if (_editing) {
                          _assignee = on ? m.id : null;
                        } else {
                          on ? _assignees.add(m.id) : _assignees.remove(m.id);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _suggesting ? null : _suggest,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('اقترح بالتساوي'),
                ),
              ),
            ],
            if (_kind == 'company') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: _projects.any((p) => p['id'] == _projectId) ? _projectId : null,
                decoration: InputDecoration(labelText: 'المشروع (اختياري)', errorText: _errors['projectId']),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('بدون مشروع')),
                  for (final p in _projects) DropdownMenuItem<int?>(value: _int(p['id']), child: Text('${p['name']}')),
                ],
                onChanged: (v) => setState(() => _projectId = v),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                value: _specialty,
                decoration: const InputDecoration(labelText: 'التخصص المطلوب (اختياري)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('أي تخصص')),
                  for (final e in specialtyLabels.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _specialty = v),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: DateField(label: 'الموعد', value: _dueDate, onChanged: (v) => setState(() => _dueDate = v), error: _errors['dueDate'])),
                const SizedBox(width: 12),
                Expanded(child: TimeField(label: 'الوقت (اختياري)', value: _dueTime, onChanged: (v) => setState(() => _dueTime = v))),
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel('الأولوية'),
            SegmentedButton<String>(
              segments: [for (final e in priorityLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {_priority},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            if (_shared) ...[
              const SizedBox(height: 16),
              FieldLabel(_kind == 'house' ? 'النقاط (الجهد من 1 إلى 5)' : 'الساعات المقدّرة'),
              Stepper2(
                value: _size,
                min: 1,
                max: _kind == 'house' ? 5 : 200,
                onChanged: (v) => setState(() => _size = v),
              ),
              if (_errors['size'] != null) Text(_errors['size']!, style: TextStyle(color: c.danger, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => setState(() => _more = !_more),
              leading: Icon(_more ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.forest),
              title: Text('خيارات إضافية', style: TextStyle(color: c.forest, fontWeight: FontWeight.w600)),
            ),
            if (_more) _extra(c),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_editing ? 'حفظ التعديلات' : 'إضافة المهمة'),
          ),
        ),
      ),
    );
  }

  Widget _extra(CampColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _details,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'التفاصيل (اختياري)', hintText: 'ما المطلوب بالضبط؟'),
          ),
          const FieldLabel('قائمة تحقق'),
          for (var i = 0; i < _checklist.length; i++)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${_checklist[i]['text']}'),
                trailing: IconButton(
                  tooltip: 'إزالة',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _checklist.removeAt(i)),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(child: TextField(controller: _newItem, decoration: const InputDecoration(hintText: 'خطوة جديدة'), onSubmitted: (_) => _addItem())),
              const SizedBox(width: 8),
              IconButton.filledTonal(tooltip: 'إضافة خطوة', onPressed: _addItem, icon: const Icon(Icons.add_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          const FieldLabel('روابط ومرفقات', hint: 'ألصق رابط الملف (Google Drive أو Figma أو غيره)'),
          for (var i = 0; i < _attachments.length; i++)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.link_rounded),
                title: Text('${_attachments[i]['label'] ?? _attachments[i]['url']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(tooltip: 'إزالة الرابط', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _attachments.removeAt(i))),
              ),
            ),
          TextField(controller: _linkUrl, textDirection: TextDirection.ltr, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _linkLabel, decoration: const InputDecoration(hintText: 'الاسم (اختياري)'))),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _addLink, child: const Text('إضافة')),
            ],
          ),
          if (_errors['attachments'] != null) Text(_errors['attachments']!, style: TextStyle(color: c.danger, fontSize: 12)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _recurrence,
            decoration: const InputDecoration(labelText: 'التكرار'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('مرة واحدة')),
              DropdownMenuItem(value: 'daily', child: Text('يومياً')),
              DropdownMenuItem(value: 'weekly', child: Text('أسبوعياً')),
            ],
            onChanged: (v) => setState(() => _recurrence = v ?? 'none'),
          ),
          if (_shared) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _approval,
              onChanged: (v) => setState(() => _needsApproval = v),
              title: const Text('تحتاج اعتمادي', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('بعد أن يُنجزها العضو تصلك للمراجعة'),
            ),
          ],
        ],
      ),
    );
  }

  void _addItem() {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add({'text': text, 'done': false});
      _newItem.clear();
    });
  }

  void _addLink() {
    var url = _linkUrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    setState(() {
      _attachments.add({'url': url, 'label': _linkLabel.text.trim().isEmpty ? null : _linkLabel.text.trim()});
      _linkUrl.clear();
      _linkLabel.clear();
    });
  }
}
