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
import 'shell.dart';

class HousingScreen extends StatelessWidget {
  const HousingScreen({super.key, this.week, this.tab});
  final String? week;
  final String? tab;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<Session>().isManager;
    final tabs = <(String, String, Widget)>[
      ('schedule', 'جدول الأسبوع', _GroupSchedule(initialWeek: week)),
      if (manager) ('distribution', 'التوزيع', _Distribution(initialWeek: week)),
      ('chores', 'أعمال السكن', const _Chores()),
      ('fairness', 'العدالة', const _Fairness()),
      ('swaps', 'التبديل', const _Swaps()),
    ];
    final initial = tabs.indexWhere((t) => t.$1 == tab);
    return DefaultTabController(
      key: ValueKey('housing-$tab-$week-${tabs.length}'),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: CampAppBar(
          title: 'السكن',
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$2)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

class WeekNav extends StatelessWidget {
  const WeekNav({super.key, required this.week, required this.onChanged});
  final String week;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = weekStartOf(adenDate());
    final label = week == current
        ? 'هذا الأسبوع'
        : week == addDays(current, 7)
            ? 'الأسبوع القادم'
            : week == addDays(current, -7)
                ? 'الأسبوع الماضي'
                : 'أسبوع ${formatDate(week)}';
    return Row(
      children: [
        IconButton(tooltip: 'الأسبوع السابق', onPressed: () => onChanged(addDays(week, -7)), icon: const Icon(Icons.chevron_right_rounded)),
        Expanded(
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${formatDate(week)} – ${formatDate(addDays(week, 6))}', style: TextStyle(color: c.muted, fontSize: 12.5)),
            ],
          ),
        ),
        IconButton(tooltip: 'الأسبوع التالي', onPressed: () => onChanged(addDays(week, 7)), icon: const Icon(Icons.chevron_left_rounded)),
      ],
    );
  }
}

// ---------------------------------------------------------------- group schedule

class _GroupSchedule extends StatefulWidget {
  const _GroupSchedule({this.initialWeek});
  final String? initialWeek;

  @override
  State<_GroupSchedule> createState() => _GroupScheduleState();
}

class _GroupScheduleState extends State<_GroupSchedule> with AutomaticKeepAliveClientMixin {
  late String _week = weekStartOf(widget.initialWeek ?? adenDate());
  int? _member;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.read<Session>();
    final c = context.c;
    return Loader(
      key: ValueKey(_week),
      load: () => session.api.get('/schedule/group', {'weekStart': _week}),
      builder: (context, data, reload) {
        final today = '${data['today']}';
        final dates = (data['dates'] as List? ?? const []).map((e) => '$e').toList();
        var tasks = listOf(data['tasks'], Task.new);
        if (_member != null) tasks = tasks.where((t) => t.assigneeId == _member).toList();
        final events = (data['events'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        final absences = (data['absences'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        final members = listOf(data['members'], User.new);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            WeekNav(week: _week, onChanged: (w) => setState(() => _week = w)),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: const Text('الجميع'), selected: _member == null, showCheckmark: false, onSelected: (_) => setState(() => _member = null)),
                  ),
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        avatar: Avatar(name: m.name, color: m.color, size: 20),
                        label: Text(m.id == session.user?.id ? 'أنا' : m.name),
                        selected: _member == m.id,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _member = m.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final d in dates) ...[
              _DayCard(
                date: d,
                isToday: d == today,
                tasks: tasks.where((t) => t.dueDate == d).toList(),
                events: events.where((e) => e['date'] == d).toList(),
                absent: absences.where((a) => '${a['startDate']}'.compareTo(d) <= 0 && '${a['endDate']}'.compareTo(d) >= 0).map((a) => '${a['userName']}').toList(),
              ),
              const SizedBox(height: 10),
            ],
            if (data['distributionStatus'] == null && session.isManager)
              Text('لم يُنشر توزيع مهام السكن لهذا الأسبوع بعد.', textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          ],
        );
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.date, required this.isToday, required this.tasks, required this.events, required this.absent});
  final String date;
  final bool isToday;
  final List<Task> tasks;
  final List<Map<String, dynamic>> events;
  final List<String> absent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isToday ? c.brass : c.line, width: isToday ? 1.5 : 1)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(formatDate(date, weekday: true), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (isToday) ...[const SizedBox(width: 8), Pill('اليوم', fg: c.brass, bg: c.brassSoft)],
                const Spacer(),
                if (absent.isNotEmpty) Text('غائب: ${absent.join('، ')}', style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
            if (tasks.isEmpty && events.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('لا شيء', style: TextStyle(color: c.muted, fontSize: 13))),
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.groups_2_outlined, size: 18, color: c.forest),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${e['title']}${e['startTime'] != null ? ' · ${formatTime(e['startTime'] as String?)}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
            for (final t in tasks)
              InkWell(
                onTap: () => context.push('/task/${t.id}'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Avatar(name: t.assigneeName ?? '؟', color: t.assigneeColor, size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${t.title}${t.kind == 'company' ? ' (شركة)' : ''}',
                          style: TextStyle(decoration: t.isDone ? TextDecoration.lineThrough : null, color: t.isDone ? c.muted : null),
                        ),
                      ),
                      if (t.dueTime != null) Text(formatTime(t.dueTime), style: TextStyle(color: c.muted, fontSize: 12)),
                      if (t.isDone) ...[const SizedBox(width: 6), Icon(Icons.check_circle_rounded, size: 18, color: c.sage)],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- distribution (manager)

class _Distribution extends StatefulWidget {
  const _Distribution({this.initialWeek});
  final String? initialWeek;

  @override
  State<_Distribution> createState() => _DistributionState();
}

class _DistributionState extends State<_Distribution> with AutomaticKeepAliveClientMixin {
  late String _week = weekStartOf(widget.initialWeek ?? addDays(adenDate(), 7));
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (!mounted) return;
      toast(context, done);
      context.read<RefreshBus>().bump();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reassign(Map<String, dynamic> item) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: '${item['choreName']} · ${formatDate(item['date'] as String?, weekday: true)}',
      fields: [F('userId', 'المكلَّف', FType.member, initial: item['userId'])],
      onSubmit: (v) => api.patch('/distribution-items/${item['id']}', {'userId': v['userId']}),
    );
    if (saved && mounted) context.read<RefreshBus>().bump();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = context.read<Session>().api;
    final c = context.c;
    return Loader(
      key: ValueKey(_week),
      load: () => api.get('/distributions/$_week'),
      builder: (context, data, reload) {
        final dist = data['distribution'] as Map?;
        final status = dist?['status'];
        final items = (data['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        final summary = (data['summary'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        final unassigned = (data['unassigned'] as num?) ?? 0;
        final dates = weekDates(_week);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            WeekNav(week: _week, onChanged: (w) => setState(() => _week = w)),
            SectionCard(
              title: dist == null ? 'لا يوجد توزيع لهذا الأسبوع' : (status == 'draft' ? 'مسودة — لم تُنشر بعد' : 'منشور'),
              subtitle: status == 'draft' ? 'راجع المكلَّفين ثم انشر لتصل المهام للجميع' : null,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (status != 'published')
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(() => api.post('/distributions/$_week/generate'), dist == null ? 'أُنشئت المسودة' : 'أُعيد التوزيع'),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(dist == null ? 'إنشاء توزيع عادل' : 'إعادة التوزيع'),
                    ),
                  if (status == 'draft')
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await confirmDialog(context, title: 'نشر التوزيع؟', body: 'ستُنشأ المهام ويصل إشعار لكل عضو.', confirmLabel: 'نشر');
                              if (ok) await _run(() => api.post('/distributions/$_week/publish'), 'نُشر التوزيع');
                            },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('نشر'),
                    ),
                ],
              ),
            ),
            if (unassigned > 0) ...[
              const SizedBox(height: 10),
              Text('${count(unassigned, itemsForms)} بلا مكلَّف — اضغط عليها لاختيار أحد', style: TextStyle(color: c.danger)),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: 'نقاط كل عضو',
                child: Column(
                  children: [
                    for (final s in summary)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Avatar(name: '${s['name']}', color: s['color'] as String?, size: 26),
                          const SizedBox(width: 10),
                          Expanded(child: Text('${s['name']}')),
                          Text(count((s['points'] as num?) ?? 0, pointsForms), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final d in dates)
              if (items.any((i) => i['date'] == d)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(formatDate(d, weekday: true), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final it in items.where((i) => i['date'] == d))
                        ListTile(
                          dense: true,
                          onTap: status == 'draft' ? () => _reassign(it) : (it['taskId'] != null ? () => context.push('/task/${it['taskId']}') : null),
                          leading: it['userId'] == null
                              ? CircleAvatar(radius: 14, backgroundColor: c.dangerSoft, child: Icon(Icons.priority_high_rounded, size: 16, color: c.danger))
                              : Avatar(name: '${it['userName']}', color: it['userColor'] as String?, size: 28),
                          title: Text('${it['choreName']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${it['userName'] ?? 'بلا مكلَّف'} · ${slotLabels[it['slot']] ?? ''} · ${count((it['points'] as num?) ?? 0, pointsForms)}'),
                          trailing: status == 'draft' ? const Icon(Icons.edit_outlined, size: 18) : (it['taskStatus'] == 'approved' ? Icon(Icons.check_circle_rounded, color: c.sage) : null),
                        ),
                    ],
                  ),
                ),
              ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- chores

const _frequencyLabels = {'daily': 'يومياً', 'days': 'أيام محددة', 'weekly': 'أسبوعياً'};
const _weekOrder = [6, 0, 1, 2, 3, 4, 5];

class _Chores extends StatelessWidget {
  const _Chores();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? ch]) async {
    final api = context.read<Session>().api;
    final bus = context.read<RefreshBus>();
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ChoreForm(chore: ch, api: api)));
    if (saved == true) {
      bus.bump();
      if (context.mounted) toast(context, ch == null ? 'أُضيف العمل' : 'حُفظ العمل');
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> ch, List<Map<String, dynamic>> list) async {
    final api = context.read<Session>().api;
    final i = list.indexOf(ch);
    final key = await showActions(context, title: '${ch['name']}', actions: [
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      const SheetAction('copy', 'نسخ', Icons.copy_rounded),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      ch['active'] == true ? const SheetAction('pause', 'إيقاف مؤقت', Icons.pause_circle_outline_rounded) : const SheetAction('resume', 'تفعيل', Icons.play_circle_outline_rounded),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'edit':
          await _edit(context, ch);
          return;
        case 'copy':
          await api.post('/chores/${ch['id']}/copy');
        case 'up':
        case 'down':
          final ids = list.map((x) => x['id']).toList();
          final j = key == 'up' ? i - 1 : i + 1;
          ids[i] = list[j]['id'];
          ids[j] = ch['id'];
          await api.post('/reorder', {'entity': 'chores', 'ids': ids});
        case 'pause':
        case 'resume':
          await api.patch('/chores/${ch['id']}', {'active': key == 'resume'});
        case 'delete':
          if (!context.mounted) return;
          await deleteWithUndo(
            context,
            remove: () => api.delete('/chores/${ch['id']}'),
            restore: () => api.post('/trash/restore', {'entity': 'chore', 'id': ch['id']}),
            message: 'حُذف العمل',
          );
          return;
      }
      if (context.mounted) context.read<RefreshBus>().bump();
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    return Loader(
      load: () => session.api.get('/chores'),
      builder: (context, data, reload) {
        final list = (data['chores'] as List? ?? const []).whereType<Map<String, dynamic>>().where((x) => x['archivedAt'] == null).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (session.isManager)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('عمل جديد')),
              ),
            const SizedBox(height: 8),
            if (list.isEmpty) const EmptyState(icon: Icons.cleaning_services_outlined, title: 'لا أعمال سكن بعد'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      onTap: session.isManager ? () => _actions(context, list[i], list) : null,
                      title: Text('${list[i]['name']}', style: TextStyle(fontWeight: FontWeight.w600, color: list[i]['active'] == true ? null : c.muted)),
                      subtitle: Text([
                        _describe(list[i]),
                        slotLabels[list[i]['slot']] ?? '',
                        count((list[i]['points'] as num?) ?? 0, pointsForms),
                        if (((list[i]['peopleCount'] as num?) ?? 1) > 1) '${list[i]['peopleCount']} أشخاص',
                        if (list[i]['active'] != true) 'موقوف',
                      ].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: session.isManager ? const Icon(Icons.more_vert_rounded) : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _describe(Map<String, dynamic> ch) {
    switch (ch['frequency']) {
      case 'days':
        final days = (ch['days'] as List? ?? const []).whereType<int>().toList();
        return _weekOrder.where(days.contains).map((d) => dayNames[d]).join('، ');
      case 'weekly':
        final d = ch['weeklyDay'];
        return d is int ? 'كل ${dayNames[d]}' : 'أسبوعياً';
      default:
        return 'يومياً';
    }
  }
}

class _ChoreForm extends StatefulWidget {
  const _ChoreForm({this.chore, required this.api});
  final Map<String, dynamic>? chore;
  final Api api;

  @override
  State<_ChoreForm> createState() => _ChoreFormState();
}

class _ChoreFormState extends State<_ChoreForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.chore?['name'] as String? ?? '');
  late String _frequency = widget.chore?['frequency'] as String? ?? 'daily';
  late Set<int> _days = {...((widget.chore?['days'] as List?) ?? const []).whereType<int>()};
  late int _weeklyDay = (widget.chore?['weeklyDay'] as int?) ?? 5;
  late int _points = (widget.chore?['points'] as int?) ?? 2;
  late int _people = (widget.chore?['peopleCount'] as int?) ?? 1;
  late String _slot = widget.chore?['slot'] as String? ?? 'any';
  bool _saving = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    if (_frequency == 'days' && _days.isEmpty) {
      setState(() => _errors = {'days': 'اختر يوماً واحداً على الأقل'});
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'frequency': _frequency,
      'days': _frequency == 'days' ? _days.toList() : <int>[],
      'weeklyDay': _frequency == 'weekly' ? _weeklyDay : null,
      'points': _points,
      'peopleCount': _people,
      'slot': _slot,
    };
    setState(() => _saving = true);
    try {
      if (widget.chore == null) {
        await widget.api.post('/chores', body);
      } else {
        await widget.api.patch('/chores/${widget.chore!['id']}', body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.fields);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton.outlined(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        IconButton.outlined(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_rounded)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: Text(widget.chore == null ? 'عمل سكن جديد' : 'تعديل العمل')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(labelText: 'اسم العمل', hintText: 'مثال: غسل الأطباق', errorText: _errors['name']),
              validator: (v) => (v ?? '').trim().length < 2 ? 'اكتب اسم العمل' : null,
            ),
            const SizedBox(height: 8),
            const Text('التكرار', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final e in _frequencyLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {_frequency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            if (_frequency == 'days') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in _weekOrder)
                    FilterChip(
                      label: Text(dayNames[d]),
                      selected: _days.contains(d),
                      onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
              if (_errors['days'] != null) Text(_errors['days']!, style: TextStyle(color: c.danger, fontSize: 12)),
            ],
            if (_frequency == 'weekly') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _weeklyDay,
                decoration: const InputDecoration(labelText: 'اليوم'),
                items: [for (final d in _weekOrder) DropdownMenuItem(value: d, child: Text(dayNames[d]))],
                onChanged: (v) => setState(() => _weeklyDay = v ?? 5),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _slot,
              decoration: const InputDecoration(labelText: 'الوقت'),
              items: [for (final e in slotLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _slot = v ?? 'any'),
            ),
            const SizedBox(height: 16),
            _stepper('النقاط (الجهد)', _points, 1, 5, (v) => setState(() => _points = v)),
            const SizedBox(height: 8),
            _stepper('عدد الأشخاص', _people, 1, 8, (v) => setState(() => _people = v)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- fairness

class _Fairness extends StatelessWidget {
  const _Fairness();

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final c = context.c;
    return Loader(
      load: () => api.get('/fairness'),
      builder: (context, data, reload) {
        final rows = (data['rows'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        final maxPts = rows.fold<num>(1, (m, r) => ((r['housePoints'] as num?) ?? 0) > m ? (r['housePoints'] as num) : m);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('هذا الأسبوع · ${formatDate(data['from'] as String?)} – ${formatDate(data['to'] as String?)}', style: TextStyle(color: c.muted)),
            const SizedBox(height: 10),
            for (final r in rows) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Avatar(name: '${r['name']}', color: r['color'] as String?, size: 28),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${((r['completion'] as num?) ?? 0).round()}% إنجاز', style: TextStyle(color: c.muted, fontSize: 12.5)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(value: ((r['housePoints'] as num?) ?? 0) / maxPts, minHeight: 8, backgroundColor: c.sunken, color: c.sage),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'السكن: ${r['houseDonePoints']} / ${r['housePoints']} نقطة · الشركة: ${r['companyDoneHours']} / ${r['companyHours']} ساعة${((r['overdue'] as num?) ?? 0) > 0 ? ' · متأخرة: ${r['overdue']}' : ''}',
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
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

// ---------------------------------------------------------------- swaps

const _swapStatus = {'pending': 'بانتظار الرد', 'accepted': 'مقبول', 'rejected': 'مرفوض', 'cancelled': 'ملغى'};

class _Swaps extends StatelessWidget {
  const _Swaps();

  Future<void> _request(BuildContext context) async {
    final session = context.read<Session>();
    final api = session.api;
    Map<String, dynamic> mine;
    try {
      mine = await api.get('/tasks', {'mine': true, 'kind': 'house,company', 'status': 'pending,in_progress,returned', 'from': adenDate()});
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    final tasks = listOf(mine['tasks'], Task.new);
    if (!context.mounted) return;
    if (tasks.isEmpty) {
      toast(context, 'لا توجد مهام قادمة يمكن تبديلها');
      return;
    }
    final saved = await showFormSheet(
      context,
      title: 'طلب تبديل',
      submitLabel: 'إرسال الطلب',
      fields: [
        F('taskId', 'المهمة', FType.select, required: true, options: {for (final t in tasks) '${t.id}': '${t.title} · ${relativeDay(t.dueDate)}'}),
        F('toUserId', 'إلى', FType.member, required: true),
        const F('note', 'السبب', FType.text, maxLength: 300, hint: 'مثال: عندي اختبار'),
      ],
      onSubmit: (v) async {
        if (v['toUserId'] == session.user?.id) throw ApiException('اختر عضواً غيرك');
        await api.post('/swaps', {'taskId': int.parse('${v['taskId']}'), 'toUserId': v['toUserId'], 'note': v['note']});
      },
    );
    if (saved && context.mounted) {
      toast(context, 'أُرسل طلب التبديل');
      context.read<RefreshBus>().bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    final me = session.user?.id;
    return Loader(
      load: () => session.api.get('/swaps'),
      builder: (context, data, reload) {
        final list = (data['swaps'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
        Future<void> decide(Map<String, dynamic> s, String d) async {
          try {
            await session.api.post('/swaps/${s['id']}/$d');
            if (!context.mounted) return;
            toast(context, switch (d) { 'accept' => 'قبلت التبديل', 'reject' => 'رفضت التبديل', _ => 'أُلغي الطلب' });
            context.read<RefreshBus>().bump();
          } on ApiException catch (e) {
            if (context.mounted) showError(context, e);
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(onPressed: () => _request(context), icon: const Icon(Icons.swap_horiz_rounded), label: const Text('طلب تبديل')),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty) const EmptyState(icon: Icons.swap_horiz_rounded, title: 'لا طلبات تبديل'),
            for (final s in list) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text('${s['fromName']} ← ${s['toName']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Pill(_swapStatus[s['status']] ?? '', fg: s['status'] == 'pending' ? c.brass : c.muted, bg: s['status'] == 'pending' ? c.brassSoft : c.sunken),
                      ]),
                      const SizedBox(height: 4),
                      Text('${s['taskTitle']} · ${relativeDay(s['taskDueDate'] as String?)}${s['counterTitle'] != null ? ' مقابل ${s['counterTitle']}' : ''}'),
                      if ((s['note'] ?? '').toString().isNotEmpty) Text('«${s['note']}»', style: TextStyle(color: c.muted)),
                      if (s['status'] == 'pending' && (s['toUserId'] == me || s['fromUserId'] == me)) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          if (s['toUserId'] == me) ...[
                            Expanded(child: FilledButton(onPressed: () => decide(s, 'accept'), child: const Text('قبول'))),
                            const SizedBox(width: 8),
                            Expanded(child: OutlinedButton(onPressed: () => decide(s, 'reject'), child: const Text('رفض'))),
                          ] else
                            Expanded(child: OutlinedButton(onPressed: () => decide(s, 'cancel'), child: const Text('إلغاء الطلب'))),
                        ]),
                      ],
                    ],
                  ),
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
