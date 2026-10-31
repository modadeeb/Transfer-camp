import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/tasks.dart';
import 'shell.dart';
import 'task_form_screen.dart';

class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key, this.tab});
  final String? tab;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<Session>().isManager;
    final tabs = <(String, String, Widget)>[
      ('mine', 'مهامي', const _MyTasks()),
      if (manager) ('manage', 'إدارة المهام', const _ManageTasks()),
      if (manager) ('approvals', 'بانتظار الاعتماد', const _Approvals()),
      ('projects', 'المشاريع', const _Projects()),
      ('events', 'الفعاليات', const _Events()),
    ];
    final initial = tabs.indexWhere((t) => t.$1 == tab);
    return DefaultTabController(
      key: ValueKey('work-$tab-${tabs.length}'),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: CampAppBar(
          title: 'العمل',
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$2)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'work-fab',
          onPressed: () => TaskFormScreen.open(context, kind: manager ? 'company' : 'personal'),
          icon: const Icon(Icons.add_rounded),
          label: Text(manager ? 'مهمة' : 'مهمة شخصية'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- my tasks

class _MyTasks extends StatefulWidget {
  const _MyTasks();

  @override
  State<_MyTasks> createState() => _MyTasksState();
}

class _MyTasksState extends State<_MyTasks> with AutomaticKeepAliveClientMixin {
  String _kind = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = context.read<Session>().api;
    final today = adenDate();
    return Loader(
      key: ValueKey(_kind),
      load: () => api.get('/tasks', {'mine': true, 'kind': _kind, 'from': addDays(today, -30)}),
      builder: (context, data, reload) {
        final all = listOf(data['tasks'], Task.new);
        final now = adenTime();
        final overdue = all.where((t) => t.isOpen && t.isOverdue(today, now)).toList();
        final todays = all.where((t) => t.dueDate == today && !overdue.contains(t) && !t.isDone).toList();
        final waiting = all.where((t) => t.status == 'submitted').toList();
        final upcoming = all.where((t) => t.isOpen && t.dueDate != null && t.dueDate!.compareTo(today) > 0).toList();
        final undated = all.where((t) => t.isOpen && t.dueDate == null).toList();
        final done = all.where((t) => t.isDone && (t.dueDate ?? '').compareTo(addDays(today, -7)) >= 0).toList();
        final groups = [
          ('متأخرة', overdue),
          ('اليوم', todays),
          ('بانتظار الاعتماد', waiting),
          ('القادمة', upcoming),
          ('بلا موعد', undated),
          ('أُنجزت مؤخراً', done.reversed.toList()),
        ].where((g) => g.$2.isNotEmpty).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _KindFilter(value: _kind, onChanged: (v) => setState(() => _kind = v)),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              const EmptyState(icon: Icons.task_alt_rounded, title: 'لا مهام', body: 'ستظهر هنا المهام المسندة إليك'),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text('${g.$1} · ${g.$2.length}', style: TextStyle(fontWeight: FontWeight.w700, color: g.$1 == 'متأخرة' ? context.c.danger : null)),
              ),
              TaskList(g.$2, today: today, nowTime: now),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _KindFilter extends StatelessWidget {
  const _KindFilter({required this.value, required this.onChanged, this.withPersonal = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool withPersonal;

  @override
  Widget build(BuildContext context) {
    final options = {'': 'الكل', 'house': 'سكن', 'company': 'شركة', if (withPersonal) 'personal': 'شخصية'};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(label: Text(e.value), selected: value == e.key, showCheckmark: false, onSelected: (_) => onChanged(e.key)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- manager: all tasks

class _ManageTasks extends StatefulWidget {
  const _ManageTasks();

  @override
  State<_ManageTasks> createState() => _ManageTasksState();
}

class _ManageTasksState extends State<_ManageTasks> with AutomaticKeepAliveClientMixin {
  String _kind = '';
  String _status = 'open';
  int? _member;
  String _q = '';
  bool _archived = false;
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _query => {
        'kind': _kind.isEmpty ? 'house,company' : _kind,
        'status': switch (_status) {
          'open' => 'pending,in_progress,returned,submitted',
          'done' => 'approved',
          _ => null,
        },
        'overdue': _status == 'overdue' ? true : null,
        'assigneeId': _member,
        'q': _q,
        'archived': _archived ? true : null,
        'from': _status == 'done' ? addDays(adenDate(), -30) : null,
      };

  Future<void> _rowActions(Task t, List<Task> list) async {
    final ta = TaskActions(context);
    final i = list.indexOf(t);
    final key = await showActions(context, title: t.title, actions: [
      const SheetAction('view', 'عرض', Icons.visibility_outlined),
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i >= 0 && i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      for (final a in ta.manage(t)) SheetAction(a.key, a.label, a.icon, danger: a.danger),
    ]);
    if (key == null || !mounted) return;
    switch (key) {
      case 'view':
        context.push('/task/${t.id}');
      case 'edit':
        await TaskFormScreen.open(context, task: t);
      case 'up':
      case 'down':
        final ids = list.map((x) => x.id).toList();
        final j = key == 'up' ? i - 1 : i + 1;
        ids[i] = list[j].id;
        ids[j] = t.id;
        try {
          await context.read<Session>().api.post('/reorder', {'entity': 'tasks', 'ids': ids});
          if (mounted) context.read<RefreshBus>().bump();
        } on ApiException catch (e) {
          if (mounted) showError(context, e);
        }
      default:
        await ta.run(t, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.read<Session>();
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث في المهام',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                          }),
                        ),
                ),
                onSubmitted: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 10),
              _KindFilter(value: _kind, withPersonal: false, onChanged: (v) => setState(() => _kind = v)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'الحالة'),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('المفتوحة')),
                        DropdownMenuItem(value: 'overdue', child: Text('المتأخرة')),
                        DropdownMenuItem(value: 'done', child: Text('المنجزة')),
                        DropdownMenuItem(value: 'all', child: Text('الكل')),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'open'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _member,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'العضو'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('كل الأعضاء')),
                        for (final m in session.members.where((m) => !m.archived)) DropdownMenuItem<int?>(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: (v) => setState(() => _member = v),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  label: const Text('المؤرشفة'),
                  selected: _archived,
                  onSelected: (v) => setState(() => _archived = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Loader(
            key: ValueKey(_query.toString()),
            load: () => session.api.get('/tasks', _query),
            builder: (context, data, reload) {
              final list = listOf(data['tasks'], Task.new);
              if (list.isEmpty) {
                return ListView(children: const [EmptyState(icon: Icons.inbox_outlined, title: 'لا مهام مطابقة')]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length + 1,
                separatorBuilder: (_, i) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text('${count(list.length, tasksForms)} · اضغط مطولاً على المهمة لخيارات أكثر', style: TextStyle(color: c.muted, fontSize: 12.5));
                  }
                  final t = list[i - 1];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: GestureDetector(
                      onLongPress: () => _rowActions(t, list),
                      child: Row(
                        children: [
                          Expanded(child: TaskRow(t, showAssignee: true)),
                          IconButton(tooltip: 'خيارات', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _rowActions(t, list)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- approvals

class _Approvals extends StatelessWidget {
  const _Approvals();

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    return Loader(
      load: () => api.get('/tasks', {'status': 'submitted', 'kind': 'house,company'}),
      builder: (context, data, reload) {
        final list = listOf(data['tasks'], Task.new);
        if (list.isEmpty) {
          return ListView(children: const [EmptyState(icon: Icons.fact_check_outlined, title: 'لا شيء بانتظار الاعتماد', body: 'كل المهام المنجزة راجعتها')]);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final t = list[i];
            final ta = TaskActions(context);
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TaskRow(t, showAssignee: true),
                  if ((t.completionNote ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('«${t.completionNote}»', style: TextStyle(color: context.c.muted)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(child: FilledButton.icon(onPressed: () => ta.run(t, 'approve'), icon: const Icon(Icons.thumb_up_alt_outlined, size: 18), label: const Text('اعتماد'))),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(onPressed: () => ta.run(t, 'return'), icon: const Icon(Icons.replay_rounded, size: 18), label: const Text('إعادة'))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------- projects

const _projectStatus = {'active': 'نشط', 'on_hold': 'متوقف مؤقتاً', 'closed': 'مغلق'};

class _Projects extends StatelessWidget {
  const _Projects();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? p]) async {
    final api = context.read<Session>().api;
    final bus = context.read<RefreshBus>();
    final saved = await showFormSheet(
      context,
      title: p == null ? 'مشروع جديد' : 'تعديل المشروع',
      fields: [
        F('name', 'اسم المشروع', FType.text, required: true, initial: p?['name'], maxLength: 80),
        F('client', 'العميل', FType.text, initial: p?['client'], maxLength: 80),
        F('description', 'الوصف', FType.multiline, initial: p?['description'], maxLength: 2000),
        F('deadline', 'موعد التسليم', FType.date, initial: p?['deadline']),
        F('status', 'الحالة', FType.select, required: true, options: _projectStatus, initial: p?['status'] ?? 'active'),
      ],
      onSubmit: (v) async {
        if (p == null) {
          await api.post('/projects', v);
        } else {
          await api.patch('/projects/${p['id']}', v);
        }
      },
    );
    if (saved) {
      bus.bump();
      if (context.mounted) toast(context, p == null ? 'أُضيف المشروع' : 'حُفظ المشروع');
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> p, List<Map<String, dynamic>> list) async {
    final api = context.read<Session>().api;
    final i = list.indexOf(p);
    final key = await showActions(context, title: '${p['name']}', actions: [
      const SheetAction('view', 'عرض المهام', Icons.visibility_outlined),
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      const SheetAction('copy', 'نسخ', Icons.copy_rounded),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'view':
          await _showProjectTasks(context, p);
        case 'edit':
          await _edit(context, p);
        case 'copy':
          await api.post('/projects/${p['id']}/copy');
          if (context.mounted) {
            context.read<RefreshBus>().bump();
            toast(context, 'نُسخ المشروع');
          }
        case 'up':
        case 'down':
          final ids = list.map((x) => x['id']).toList();
          final j = key == 'up' ? i - 1 : i + 1;
          ids[i] = list[j]['id'];
          ids[j] = p['id'];
          await api.post('/reorder', {'entity': 'projects', 'ids': ids});
          if (context.mounted) context.read<RefreshBus>().bump();
        case 'delete':
          final ok = await confirmDialog(context, title: 'حذف المشروع؟', body: 'تبقى مهامه كما هي بلا مشروع. يمكنك استعادته خلال 30 يوماً.', confirmLabel: 'حذف', danger: true);
          if (!ok || !context.mounted) return;
          await deleteWithUndo(
            context,
            remove: () => api.delete('/projects/${p['id']}'),
            restore: () => api.post('/trash/restore', {'entity': 'project', 'id': p['id']}),
            message: 'حُذف المشروع',
          );
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _showProjectTasks(BuildContext context, Map<String, dynamic> p) {
    final api = context.read<Session>().api;
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${p['name']}')),
        body: Loader(
          load: () => api.get('/tasks', {'projectId': p['id'], 'kind': 'company'}),
          builder: (context, data, reload) {
            final list = listOf(data['tasks'], Task.new);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (list.isEmpty) const EmptyState(icon: Icons.inbox_outlined, title: 'لا مهام في هذا المشروع') else TaskList(list, showAssignee: true),
              ],
            );
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    return Loader(
      load: () => session.api.get('/projects'),
      builder: (context, data, reload) {
        final list = (data['projects'] as List? ?? const []).whereType<Map<String, dynamic>>().where((p) => p['archivedAt'] == null).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (session.isManager)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('مشروع جديد')),
              ),
            const SizedBox(height: 8),
            if (list.isEmpty) const EmptyState(icon: Icons.folder_open_outlined, title: 'لا مشاريع بعد'),
            for (final p in list) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => session.isManager ? _actions(context, p, list) : _showProjectTasks(context, p),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                            Pill(_projectStatus[p['status']] ?? '', fg: p['status'] == 'active' ? c.sage : c.muted, bg: p['status'] == 'active' ? c.sageSoft : c.sunken),
                          ],
                        ),
                        if (p['client'] != null) Text('${p['client']}', style: TextStyle(color: c.muted)),
                        const SizedBox(height: 10),
                        _Progress(done: (p['doneCount'] as num?) ?? 0, total: (p['taskCount'] as num?) ?? 0),
                        if (p['deadline'] != null) ...[
                          const SizedBox(height: 6),
                          Text('التسليم: ${formatDate(p['deadline'] as String, weekday: true)}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});
  final num done;
  final num total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 7, backgroundColor: c.sunken, color: c.sage),
          ),
        ),
        const SizedBox(width: 10),
        Text('$done / $total', style: TextStyle(color: c.muted, fontSize: 12.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------- events

const _eventKinds = {'meeting': 'اجتماع', 'deadline': 'موعد تسليم', 'other': 'أخرى'};

class _Events extends StatelessWidget {
  const _Events();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? e]) async {
    final api = context.read<Session>().api;
    final bus = context.read<RefreshBus>();
    final saved = await showFormSheet(
      context,
      title: e == null ? 'فعالية جديدة' : 'تعديل الفعالية',
      fields: [
        F('title', 'العنوان', FType.text, required: true, initial: e?['title'], maxLength: 100),
        F('kind', 'النوع', FType.select, required: true, options: _eventKinds, initial: e?['kind'] ?? 'meeting'),
        F('date', 'التاريخ', FType.date, required: true, initial: e?['date'] ?? adenDate()),
        F('startTime', 'من', FType.time, initial: e?['startTime']),
        F('endTime', 'إلى', FType.time, initial: e?['endTime']),
        F('everyone', 'للجميع', FType.toggle, initial: e == null ? true : e['everyone'] == true, hint: 'أطفئه لاختيار أعضاء محددين'),
        F('memberIds', 'الأعضاء (إن لم تكن للجميع)', FType.members, initial: ((e?['memberIds'] as List?) ?? const []).whereType<int>()),
        F('notes', 'ملاحظات', FType.multiline, initial: e?['notes'], maxLength: 1000),
      ],
      onSubmit: (v) async {
        if (e == null) {
          await api.post('/events', v);
        } else {
          await api.patch('/events/${e['id']}', v);
        }
      },
    );
    if (saved) {
      bus.bump();
      if (context.mounted) toast(context, e == null ? 'أُضيفت الفعالية' : 'حُفظت الفعالية');
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> e) async {
    final api = context.read<Session>().api;
    final key = await showActions(context, title: '${e['title']}', actions: const [
      SheetAction('edit', 'تعديل', Icons.edit_outlined),
      SheetAction('copy', 'نسخ', Icons.copy_rounded),
      SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'edit':
          await _edit(context, e);
        case 'copy':
          await api.post('/events/${e['id']}/copy');
          if (context.mounted) {
            context.read<RefreshBus>().bump();
            toast(context, 'نُسخت الفعالية');
          }
        case 'delete':
          await deleteWithUndo(
            context,
            remove: () => api.delete('/events/${e['id']}'),
            restore: () => api.post('/events/${e['id']}/restore'),
            message: 'حُذفت الفعالية',
          );
      }
    } on ApiException catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    final today = adenDate();
    return Loader(
      load: () => session.api.get('/events', {'from': addDays(today, -7)}),
      builder: (context, data, reload) {
        final list = (data['events'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (session.isManager)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('فعالية جديدة')),
              ),
            const SizedBox(height: 8),
            if (list.isEmpty) const EmptyState(icon: Icons.event_outlined, title: 'لا فعاليات قادمة'),
            for (final e in list) ...[
              Card(
                child: ListTile(
                  onTap: session.isManager ? () => _actions(context, e) : null,
                  leading: CircleAvatar(
                    backgroundColor: e['kind'] == 'deadline' ? c.dangerSoft : c.sageSoft,
                    child: Icon(e['kind'] == 'deadline' ? Icons.flag_outlined : Icons.groups_2_outlined, color: e['kind'] == 'deadline' ? c.danger : c.sage),
                  ),
                  title: Text('${e['title']}', style: TextStyle(fontWeight: FontWeight.w600, color: '${e['date']}'.compareTo(today) < 0 ? c.muted : null)),
                  subtitle: Text([
                    relativeDay(e['date'] as String?),
                    if (e['startTime'] != null) '${formatTime(e['startTime'] as String?)}${e['endTime'] != null ? ' – ${formatTime(e['endTime'] as String?)}' : ''}',
                    if (e['everyone'] != true) 'لأعضاء محددين',
                  ].join(' · ')),
                  trailing: session.isManager ? const Icon(Icons.more_vert_rounded) : null,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
