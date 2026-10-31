import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import '../widgets/form_sheet.dart';
import '../widgets/prayers.dart';
import 'housing_screen.dart' show WeekNav;
import 'shell.dart';

List<Map<String, dynamic>> _maps(Object? v) => (v is List ? v : const []).whereType<Map<String, dynamic>>().toList();

const goalCategories = {'religious': 'ديني', 'study': 'دراسي', 'health': 'صحي', 'money': 'مالي', 'work': 'مهني', 'personal': 'شخصي'};
const personalCategories = {'food': 'طعام', 'transport': 'مواصلات', 'study': 'دراسة', 'phone': 'اتصالات', 'personal': 'شخصي', 'other': 'أخرى'};
const incomeSources = {'salary': 'راتب', 'freelance': 'عمل حر', 'family': 'من الأهل', 'gift': 'هدية', 'other': 'أخرى'};
const slotKinds = {'university': 'جامعة', 'work': 'عمل', 'other': 'أخرى'};
const _weekOrder = [6, 0, 1, 2, 3, 4, 5];

class MeScreen extends StatelessWidget {
  const MeScreen({super.key, this.tab});
  final String? tab;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('schedule', 'جدولي'),
      ('budget', 'ميزانيتي'),
      ('worship', 'عبادتي'),
      ('health', 'صحتي'),
      ('goals', 'أهدافي'),
      ('habits', 'عاداتي'),
    ];
    final initial = tabs.indexWhere((t) => t.$1 == tab);
    return DefaultTabController(
      key: ValueKey('me-$tab'),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: CampAppBar(
          title: 'أنا',
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$2)]),
        ),
        body: const TabBarView(children: [_MySchedule(), _Budget(), _Worship(), _Health(), _Goals(), _Habits()]),
      ),
    );
  }
}

// ---------------------------------------------------------------- my schedule

class _MySchedule extends StatefulWidget {
  const _MySchedule();

  @override
  State<_MySchedule> createState() => _MyScheduleState();
}

class _MyScheduleState extends State<_MySchedule> with AutomaticKeepAliveClientMixin {
  String _week = weekStartOf(adenDate());

  @override
  bool get wantKeepAlive => true;

  Future<void> _editSlots(List<Map<String, dynamic>> slots) async {
    final session = context.read<Session>();
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SlotsEditor(api: session.api, userId: session.user!.id, slots: slots),
    ));
    if (saved == true && mounted) {
      toast(context, 'حُفظ جدولك');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _addAbsence() async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: 'سأكون غائباً',
      fields: [
        F('startDate', 'من', FType.date, required: true, initial: adenDate()),
        F('endDate', 'إلى', FType.date, required: true, initial: adenDate()),
        const F('reason', 'السبب', FType.text, maxLength: 120, hint: 'مثال: سفر'),
      ],
      onSubmit: (v) => api.post('/absences', v),
    );
    if (saved && mounted) {
      toast(context, 'سُجّل الغياب — لن تُسنَد إليك مهام سكن فيه');
      context.read<RefreshBus>().bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = context.read<Session>().api;
    final c = context.c;
    return Loader(
      key: ValueKey(_week),
      load: () => api.get('/schedule/me', {'weekStart': _week}),
      builder: (context, data, reload) {
        final today = '${data['today']}';
        final dates = (data['dates'] as List? ?? const []).map((e) => '$e').toList();
        final tasks = listOf(data['tasks'], Task.new);
        final slots = _maps(data['slots']);
        final events = _maps(data['events']);
        final absences = _maps(data['absences']);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            WeekNav(week: _week, onChanged: (w) => setState(() => _week = w)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => _editSlots(slots), icon: const Icon(Icons.school_outlined, size: 18), label: const Text('أوقات الجامعة والعمل')),
              OutlinedButton.icon(onPressed: _addAbsence, icon: const Icon(Icons.flight_takeoff_rounded, size: 18), label: const Text('غياب')),
            ]),
            const SizedBox(height: 10),
            for (final d in dates) ...[
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: d == today ? c.brass : c.line, width: d == today ? 1.5 : 1)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(formatDate(d, weekday: true), style: const TextStyle(fontWeight: FontWeight.w700)),
                      for (final a in absences.where((a) => '${a['startDate']}'.compareTo(d) <= 0 && '${a['endDate']}'.compareTo(d) >= 0))
                        Padding(padding: const EdgeInsets.only(top: 6), child: Text('غياب${a['reason'] != null ? ': ${a['reason']}' : ''}', style: TextStyle(color: c.brass))),
                      for (final s in slots.where((s) => s['dow'] == dayOfWeek(d)))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.school_outlined, size: 17, color: c.muted),
                            const SizedBox(width: 8),
                            Text('${s['label'] ?? slotKinds[s['kind']] ?? ''} · ${formatTime(s['startTime'] as String?)} – ${formatTime(s['endTime'] as String?)}', style: TextStyle(color: c.muted)),
                          ]),
                        ),
                      for (final e in events.where((e) => e['date'] == d))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.groups_2_outlined, size: 17, color: c.forest),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${e['title']}${e['startTime'] != null ? ' · ${formatTime(e['startTime'] as String?)}' : ''}')),
                          ]),
                        ),
                      for (final t in tasks.where((t) => t.dueDate == d))
                        InkWell(
                          onTap: () => context.push('/task/${t.id}'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              Icon(t.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: t.isDone ? c.sage : c.line),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t.title, style: TextStyle(decoration: t.isDone ? TextDecoration.lineThrough : null, color: t.isDone ? c.muted : null))),
                              if (t.dueTime != null) Text(formatTime(t.dueTime), style: TextStyle(color: c.muted, fontSize: 12)),
                            ]),
                          ),
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

class _SlotsEditor extends StatefulWidget {
  const _SlotsEditor({required this.api, required this.userId, required this.slots});
  final Api api;
  final int userId;
  final List<Map<String, dynamic>> slots;

  @override
  State<_SlotsEditor> createState() => _SlotsEditorState();
}

class _SlotsEditorState extends State<_SlotsEditor> {
  late final List<Map<String, dynamic>> _slots = widget.slots
      .map((s) => {'dow': s['dow'], 'startTime': s['startTime'], 'endTime': s['endTime'], 'kind': s['kind'] ?? 'university', 'label': s['label']})
      .toList();
  bool _saving = false;

  Future<void> _save() async {
    for (final s in _slots) {
      if ('${s['endTime']}'.compareTo('${s['startTime']}') <= 0) {
        toast(context, 'وقت النهاية يجب أن يكون بعد البداية', error: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.api.put('/members/${widget.userId}/slots', {'slots': _slots});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أوقات الجامعة والعمل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('لا تُسنَد إليك مهام سكن في هذه الأوقات.', style: TextStyle(color: context.c.muted)),
          const SizedBox(height: 12),
          for (var i = 0; i < _slots.length; i++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _slots[i]['dow'] as int,
                          decoration: const InputDecoration(labelText: 'اليوم'),
                          items: [for (final d in _weekOrder) DropdownMenuItem(value: d, child: Text(dayNames[d]))],
                          onChanged: (v) => setState(() => _slots[i]['dow'] = v ?? 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _slots[i]['kind'] as String,
                          decoration: const InputDecoration(labelText: 'النوع'),
                          items: [for (final e in slotKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: (v) => setState(() => _slots[i]['kind'] = v ?? 'university'),
                        ),
                      ),
                      IconButton(tooltip: 'حذف', onPressed: () => setState(() => _slots.removeAt(i)), icon: Icon(Icons.delete_outline_rounded, color: context.c.danger)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TimeField(label: 'من', value: _slots[i]['startTime'] as String?, clearable: false, onChanged: (v) => setState(() => _slots[i]['startTime'] = v))),
                      const SizedBox(width: 10),
                      Expanded(child: TimeField(label: 'إلى', value: _slots[i]['endTime'] as String?, clearable: false, onChanged: (v) => setState(() => _slots[i]['endTime'] = v))),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => setState(() => _slots.add({'dow': 0, 'startTime': '08:00', 'endTime': '12:00', 'kind': 'university', 'label': null})),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة وقت'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ'))),
      ),
    );
  }
}

// ---------------------------------------------------------------- budget

class _Budget extends StatelessWidget {
  const _Budget();

  Future<void> _startWeek(BuildContext context, Map<String, dynamic> data) async {
    final api = context.read<Session>().api;
    final hasWeek = data['week'] != null;
    final fundShare = (data['fundShareDue'] as num?) ?? 0;
    final saved = await showFormSheet(
      context,
      title: hasWeek ? 'أغلق الأسبوع وابدأ جديداً' : 'ابدأ أسبوعك',
      submitLabel: 'ابدأ',
      fields: [
        const F('income', 'دخل هذا الأسبوع', FType.amount, required: true, min: 0),
        const F('source', 'المصدر', FType.select, required: true, options: incomeSources, initial: 'salary'),
        F('fund', 'حصة الصندوق كمصروف أساسي', FType.amount, initial: fundShare > 0 ? fundShare : null, min: 0, hint: 'اتركه فارغاً إن لم يكن عليك شيء'),
        if (hasWeek) const F('leftover', 'ما تبقى من الأسبوع الحالي', FType.select, required: true, options: {'carry': 'يُرحَّل للأسبوع الجديد', 'save': 'يُدّخر'}, initial: 'carry'),
      ],
      onSubmit: (v) async {
        final fund = v['fund'] as int?;
        await api.post('/budget/weeks', {
          'income': v['income'] ?? 0,
          'source': v['source'],
          'essentials': [if (fund != null && fund > 0) {'title': 'حصة الصندوق', 'amount': fund}],
          if (hasWeek) 'leftover': v['leftover'],
        });
      },
    );
    if (saved && context.mounted) {
      toast(context, 'بدأ أسبوعك');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _entry(BuildContext context, String kind, [Map<String, dynamic>? e]) async {
    final api = context.read<Session>().api;
    final fields = switch (kind) {
      'expenses' => [
          F('amount', 'المبلغ', FType.amount, required: true, initial: e?['amount']),
          F('category', 'التصنيف', FType.select, required: true, options: personalCategories, initial: e?['category'] ?? 'food'),
          F('date', 'التاريخ', FType.date, required: true, initial: e?['date'] ?? adenDate()),
          F('note', 'ملاحظة', FType.text, initial: e?['note'], maxLength: 200),
        ],
      'incomes' => [
          F('amount', 'المبلغ', FType.amount, required: true, initial: e?['amount']),
          F('source', 'المصدر', FType.select, required: true, options: incomeSources, initial: e?['source'] ?? 'other'),
          F('date', 'التاريخ', FType.date, required: true, initial: e?['date'] ?? adenDate()),
          F('note', 'ملاحظة', FType.text, initial: e?['note'], maxLength: 200),
        ],
      _ => [
          F('title', 'البيان', FType.text, required: true, initial: e?['title'], maxLength: 60),
          F('amount', 'المبلغ', FType.amount, required: true, initial: e?['amount'], min: 0),
        ],
    };
    final titles = {'expenses': 'مصروف', 'incomes': 'دخل', 'essentials': 'مصروف أساسي'};
    final saved = await showFormSheet(
      context,
      title: '${e == null ? 'إضافة' : 'تعديل'} ${titles[kind]}',
      fields: fields,
      onSubmit: (v) => e == null ? api.post('/budget/$kind', v) : api.patch('/budget/$kind/${e['id']}', v),
    );
    if (saved && context.mounted) context.read<RefreshBus>().bump();
  }

  Future<void> _entryActions(BuildContext context, String kind, Map<String, dynamic> e) async {
    final api = context.read<Session>().api;
    final key = await showActions(context, title: formatMoney(e['amount'] as num?), actions: [
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      if (kind != 'essentials') const SheetAction('copy', 'نسخ لليوم', Icons.copy_rounded),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'edit':
          await _entry(context, kind, e);
        case 'copy':
          await api.post('/budget/$kind/${e['id']}/copy');
          if (context.mounted) context.read<RefreshBus>().bump();
        case 'delete':
          await deleteWithUndo(context, remove: () => api.delete('/budget/$kind/${e['id']}'), message: 'حُذف');
      }
    } on ApiException catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final c = context.c;
    return Loader(
      load: () => api.get('/budget'),
      builder: (context, data, reload) {
        if (data['week'] == null) {
          return ListView(children: [
            EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'لم يبدأ أسبوعك',
              body: 'اكتب دخلك والمصاريف الأساسية، ويحسب لك التطبيق كم يمكنك أن تصرف كل يوم.',
              action: FilledButton(onPressed: () => _startWeek(context, data), child: const Text('ابدأ الأسبوع')),
            ),
          ]);
        }
        final s = data['summary'] as Map? ?? const {};
        final week = data['week'] as Map;
        final days = _maps(s['days']);
        final expenses = _maps(data['expenses']);
        final incomes = _maps(data['incomes']);
        final essentials = _maps(data['essentials']);
        final leftToday = (s['leftToday'] as num?) ?? 0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('المتبقي لك اليوم', style: TextStyle(color: c.muted)),
                    Text(formatMoney(leftToday), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: leftToday < 0 ? c.danger : c.forest)),
                    Text('المسموح اليوم ${formatMoney(s['allowedToday'] as num?)} · صرفت ${formatMoney(s['spentToday'] as num?)}', style: TextStyle(color: c.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => _entry(context, 'expenses'), icon: const Icon(Icons.remove_circle_outline_rounded), label: const Text('سجّل مصروفاً')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'الأسبوع',
              subtitle: '${formatDate(week['startDate'] as String?)} – ${formatDate(week['endDate'] as String?)} · باقي ${(s['daysLeft'] as num?) ?? 0} أيام',
              child: Column(
                children: [
                  _line(context, 'الدخل (مع المرحَّل)', s['totalIncome']),
                  _line(context, 'المصاريف الأساسية', s['essentialsTotal']),
                  _line(context, 'المتاح للصرف', s['remaining']),
                  _line(context, 'صرفت حتى الآن', s['spentTotal']),
                  const Divider(),
                  _line(context, 'المتبقي للأسبوع', s['left'], bold: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Column(children: [
                            Text(dayInitials[dayOfWeek('${d['date']}')], style: TextStyle(fontSize: 11, color: c.muted)),
                            const SizedBox(height: 4),
                            Container(
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                color: d['past'] == true ? (((d['spent'] as num?) ?? 0) > 0 ? c.sage : c.line) : (d['allowed'] != null ? c.brassSoft : c.sunken),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EntryList(
              title: 'مصاريفي',
              items: expenses,
              label: (e) => '${personalCategories[e['category']] ?? ''}${e['note'] != null ? ' · ${e['note']}' : ''}',
              sub: (e) => relativeDay(e['date'] as String?),
              onAdd: () => _entry(context, 'expenses'),
              onTap: (e) => _entryActions(context, 'expenses', e),
            ),
            const SizedBox(height: 12),
            _EntryList(
              title: 'الدخل',
              items: incomes,
              label: (e) => '${incomeSources[e['source']] ?? ''}${e['note'] != null ? ' · ${e['note']}' : ''}',
              sub: (e) => relativeDay(e['date'] as String?),
              onAdd: () => _entry(context, 'incomes'),
              onTap: (e) => _entryActions(context, 'incomes', e),
            ),
            const SizedBox(height: 12),
            _EntryList(
              title: 'المصاريف الأساسية',
              items: essentials,
              label: (e) => '${e['title']}',
              onAdd: () => _entry(context, 'essentials'),
              onTap: (e) => _entryActions(context, 'essentials', e),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => _startWeek(context, data), child: const Text('أغلق الأسبوع وابدأ جديداً')),
          ],
        );
      },
    );
  }

  Widget _line(BuildContext context, String label, Object? value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? null : context.c.muted, fontWeight: bold ? FontWeight.w700 : null))),
          Text(formatMoney(value as num?), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.title, required this.items, required this.label, this.sub, required this.onAdd, required this.onTap});
  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>)? sub;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      trailing: TextButton(onPressed: onAdd, child: const Text('إضافة')),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: items.isEmpty
          ? Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('لا شيء بعد', style: TextStyle(color: context.c.muted)))
          : Column(children: [
              for (final e in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => onTap(e),
                  title: Text(label(e)),
                  subtitle: sub == null ? null : Text(sub!(e)),
                  trailing: Text(formatMoney(e['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------- worship

class _Worship extends StatefulWidget {
  const _Worship();

  @override
  State<_Worship> createState() => _WorshipState();
}

class _WorshipState extends State<_Worship> with AutomaticKeepAliveClientMixin {
  String _week = weekStartOf(adenDate());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = context.read<Session>().api;
    final c = context.c;
    final today = adenDate();
    return Loader(
      key: ValueKey(_week),
      load: () => api.get('/me/prayers', {'from': _week, 'to': addDays(_week, 6)}),
      builder: (context, data, reload) {
        final logs = _maps(data['logs']);
        final times = (data['times'] as Map? ?? const {});
        final dates = weekDates(_week).where((d) => d.compareTo(today) <= 0).toList().reversed.toList();
        final total = logs.length;
        final possible = dates.length * 5;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            WeekNav(week: _week, onChanged: (w) => setState(() => _week = w)),
            if (possible > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text('صليت $total من $possible هذا الأسبوع', style: TextStyle(color: c.muted)),
              ),
            if (dates.isEmpty) const EmptyState(icon: Icons.mosque_outlined, title: 'هذا الأسبوع لم يبدأ بعد'),
            for (final d in dates) ...[
              SectionCard(
                title: d == today ? 'اليوم' : formatDate(d, weekday: true),
                child: _DayPrayers(
                  date: d,
                  times: (times[d] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
                  done: logs.where((l) => l['date'] == d).map((l) => '${l['prayer']}').toSet(),
                  now: d == today ? adenTime() : null,
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

class _DayPrayers extends StatefulWidget {
  const _DayPrayers({required this.date, required this.times, required this.done, this.now});
  final String date;
  final Map<String, String> times;
  final Set<String> done;
  final String? now;

  @override
  State<_DayPrayers> createState() => _DayPrayersState();
}

class _DayPrayersState extends State<_DayPrayers> {
  late Set<String> _done = {...widget.done};

  @override
  void didUpdateWidget(covariant _DayPrayers old) {
    super.didUpdateWidget(old);
    _done = {...widget.done};
  }

  Future<void> _toggle(String key) async {
    final on = !_done.contains(key);
    setState(() => on ? _done.add(key) : _done.remove(key));
    try {
      await context.read<Session>().api.put('/me/prayers', {'date': widget.date, 'prayer': key, 'done': on});
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => on ? _done.remove(key) : _done.add(key));
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PrayerRow(times: widget.times, done: _done, now: widget.now, onToggle: _toggle);
}

// ---------------------------------------------------------------- health

class _Health extends StatelessWidget {
  const _Health();

  Future<void> _sleep(BuildContext context, [Map<String, dynamic>? log]) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: 'نومي',
      fields: [
        F('date', 'صباح يوم', FType.date, required: true, initial: log?['date'] ?? adenDate()),
        F('sleptAt', 'نمت الساعة', FType.time, initial: log?['sleptAt'] ?? '23:00'),
        F('wokeAt', 'استيقظت الساعة', FType.time, initial: log?['wokeAt'] ?? '06:00'),
      ],
      onSubmit: (v) {
        if (v['sleptAt'] == null || v['wokeAt'] == null) throw ApiException('اختر وقت النوم والاستيقاظ');
        return api.put('/me/sleep', v);
      },
    );
    if (saved && context.mounted) context.read<RefreshBus>().bump();
  }

  Future<void> _workout(BuildContext context) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: 'تمرين',
      fields: [
        const F('type', 'النوع', FType.text, required: true, maxLength: 40, hint: 'مثال: جري، كرة، حديد'),
        const F('durationMin', 'المدة بالدقائق', FType.integer, min: 1, max: 600),
        F('date', 'التاريخ', FType.date, required: true, initial: adenDate()),
      ],
      onSubmit: (v) => api.post('/me/workouts', v),
    );
    if (saved && context.mounted) {
      toast(context, 'أحسنت 💪');
      context.read<RefreshBus>().bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final c = context.c;
    return Loader(
      load: () async {
        final sleep = await api.get('/me/sleep');
        final workouts = await api.get('/me/workouts');
        return {'sleep': sleep['logs'], 'workouts': workouts['workouts']};
      },
      builder: (context, data, reload) {
        final sleep = _maps(data['sleep']).reversed.toList();
        final workouts = _maps(data['workouts']).reversed.toList();
        final avg = sleep.isEmpty ? 0 : sleep.map((s) => (s['minutes'] as num?) ?? 0).reduce((a, b) => a + b) ~/ sleep.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SectionCard(
              title: 'النوم هذا الأسبوع',
              subtitle: sleep.isEmpty ? null : 'المتوسط ${formatDuration(avg.toInt())}',
              trailing: TextButton(onPressed: () => _sleep(context), child: const Text('تسجيل')),
              child: sleep.isEmpty
                  ? Text('لم تسجّل نومك بعد', style: TextStyle(color: c.muted))
                  : Column(children: [
                      for (final s in sleep)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onTap: () => _sleep(context, s),
                          onLongPress: () => deleteWithUndo(context, remove: () => api.delete('/me/sleep/${s['date']}'), message: 'حُذف'),
                          leading: Icon(Icons.bedtime_outlined, color: c.sage),
                          title: Text(formatDate(s['date'] as String?, weekday: true)),
                          subtitle: Text('${formatTime(s['sleptAt'] as String?)} ← ${formatTime(s['wokeAt'] as String?)}'),
                          trailing: Text(formatDuration(((s['minutes'] as num?) ?? 0).toInt()), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'التمارين هذا الأسبوع',
              subtitle: '${workouts.map((w) => w['date']).toSet().length} أيام',
              trailing: TextButton(onPressed: () => _workout(context), child: const Text('تسجيل')),
              child: workouts.isEmpty
                  ? Text('لا تمارين بعد', style: TextStyle(color: c.muted))
                  : Column(children: [
                      for (final w in workouts)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.fitness_center_rounded, color: c.sage),
                          title: Text('${w['type']}'),
                          subtitle: Text(relativeDay(w['date'] as String?)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (w['durationMin'] != null) Text('${w['durationMin']} د'),
                            IconButton(
                              tooltip: 'حذف',
                              icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                              onPressed: () => deleteWithUndo(context, remove: () => api.delete('/me/workouts/${w['id']}'), message: 'حُذف التمرين'),
                            ),
                          ]),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- goals

class _Goals extends StatelessWidget {
  const _Goals();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? g]) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: g == null ? 'هدف جديد' : 'تعديل الهدف',
      fields: [
        F('title', 'الهدف', FType.text, required: true, initial: g?['title'], maxLength: 100),
        F('category', 'المجال', FType.select, required: true, options: goalCategories, initial: g?['category'] ?? 'personal'),
        F('targetDate', 'الموعد المستهدف', FType.date, initial: g?['targetDate']),
      ],
      onSubmit: (v) => g == null ? api.post('/me/goals', v) : api.patch('/me/goals/${g['id']}', v),
    );
    if (saved && context.mounted) context.read<RefreshBus>().bump();
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> g, List<Map<String, dynamic>> list) async {
    final api = context.read<Session>().api;
    final i = list.indexOf(g);
    final key = await showActions(context, title: '${g['title']}', actions: [
      const SheetAction('step', 'إضافة خطوة', Icons.add_task_rounded),
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      const SheetAction('archive', 'أرشفة', Icons.archive_outlined),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'step':
          final title = await promptText(context, title: 'خطوة جديدة', label: 'الخطوة', confirmLabel: 'إضافة', maxLength: 120);
          if (title == null) return;
          await api.post('/me/goals/${g['id']}/steps', {'title': title});
        case 'edit':
          await _edit(context, g);
          return;
        case 'up':
        case 'down':
          final ids = list.map((x) => x['id']).toList();
          final j = key == 'up' ? i - 1 : i + 1;
          ids[i] = list[j]['id'];
          ids[j] = g['id'];
          await api.post('/reorder', {'entity': 'goals', 'ids': ids});
        case 'archive':
          await api.post('/me/goals/${g['id']}/archive');
        case 'delete':
          if (!context.mounted) return;
          await deleteWithUndo(
            context,
            remove: () => api.delete('/me/goals/${g['id']}'),
            restore: () => api.post('/trash/restore', {'entity': 'goal', 'id': g['id']}),
            message: 'حُذف الهدف',
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
    final api = context.read<Session>().api;
    final c = context.c;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(heroTag: 'goal-fab', onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('هدف')),
      body: Loader(
        load: () => api.get('/me/goals'),
        builder: (context, data, reload) {
          final list = _maps(data['goals']).where((g) => g['archivedAt'] == null).toList();
          if (list.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.flag_outlined, title: 'لا أهداف بعد', body: 'قسّم هدفك إلى خطوات صغيرة')]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              for (final g in list) ...[
                SectionCard(
                  title: '${g['title']}',
                  subtitle: [goalCategories[g['category']] ?? '', if (g['targetDate'] != null) 'حتى ${formatDate(g['targetDate'] as String?)}'].join(' · '),
                  trailing: IconButton(tooltip: 'خيارات', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _actions(context, g, list)),
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: ((g['progress'] as num?) ?? 0) / 100, minHeight: 7, backgroundColor: c.sunken, color: c.sage),
                        ),
                      ),
                      for (final s in _maps(g['steps']))
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: s['doneAt'] != null,
                          title: Text('${s['title']}', style: TextStyle(decoration: s['doneAt'] != null ? TextDecoration.lineThrough : null, color: s['doneAt'] != null ? c.muted : null)),
                          secondary: IconButton(
                            tooltip: 'حذف الخطوة',
                            icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                            onPressed: () async {
                              try {
                                await api.delete('/me/goal-steps/${s['id']}');
                                if (context.mounted) context.read<RefreshBus>().bump();
                              } on ApiException catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          ),
                          onChanged: (v) async {
                            try {
                              await api.patch('/me/goal-steps/${s['id']}', {'done': v ?? false});
                              if (context.mounted) context.read<RefreshBus>().bump();
                            } on ApiException catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- habits

class _Habits extends StatelessWidget {
  const _Habits();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? h]) async {
    final api = context.read<Session>().api;
    final days = h?['days'];
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _HabitForm(api: api, habit: h, initialDays: days is List ? days.whereType<int>().toSet() : null),
    ));
    if (saved == true && context.mounted) context.read<RefreshBus>().bump();
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> h, List<Map<String, dynamic>> list) async {
    final api = context.read<Session>().api;
    final i = list.indexOf(h);
    final key = await showActions(context, title: '${h['title']}', actions: [
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'edit':
          await _edit(context, h);
        case 'up':
        case 'down':
          final ids = list.map((x) => x['id']).toList();
          final j = key == 'up' ? i - 1 : i + 1;
          ids[i] = list[j]['id'];
          ids[j] = h['id'];
          await api.post('/reorder', {'entity': 'habits', 'ids': ids});
          if (context.mounted) context.read<RefreshBus>().bump();
        case 'delete':
          await deleteWithUndo(
            context,
            remove: () => api.delete('/me/habits/${h['id']}'),
            restore: () => api.post('/trash/restore', {'entity': 'habit', 'id': h['id']}),
            message: 'حُذفت العادة',
          );
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final c = context.c;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(heroTag: 'habit-fab', onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('عادة')),
      body: Loader(
        load: () => api.get('/me/habits'),
        builder: (context, data, reload) {
          final list = _maps(data['habits']).where((h) => h['archivedAt'] == null).toList();
          final today = '${data['today']}';
          if (list.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.repeat_rounded, title: 'لا عادات بعد', body: 'ابدأ بعادة صغيرة يومية')]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              for (final h in list) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${h['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text('سلسلة ${h['streak'] ?? 0} ${((h['streak'] as num?) ?? 0) == 1 ? 'يوم' : 'أيام'}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                            ]),
                          ),
                          IconButton(tooltip: 'خيارات', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _actions(context, h, list)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          for (final d in _maps(h['week']))
                            Expanded(
                              child: _HabitDot(
                                habitId: h['id'] as int,
                                date: '${d['date']}',
                                due: d['due'] == true,
                                done: d['done'] == true,
                                future: '${d['date']}'.compareTo(today) > 0,
                                isToday: d['date'] == today,
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HabitDot extends StatelessWidget {
  const _HabitDot({required this.habitId, required this.date, required this.due, required this.done, required this.future, required this.isToday});
  final int habitId;
  final String date;
  final bool due;
  final bool done;
  final bool future;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(children: [
      Text(dayInitials[dayOfWeek(date)], style: TextStyle(fontSize: 11, color: isToday ? c.brass : c.muted, fontWeight: isToday ? FontWeight.w700 : null)),
      const SizedBox(height: 4),
      InkResponse(
        onTap: future
            ? null
            : () async {
                try {
                  await context.read<Session>().api.post('/me/habits/$habitId/toggle', {'date': date, 'done': !done});
                  if (context.mounted) context.read<RefreshBus>().bump();
                } on ApiException catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
        radius: 20,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? c.sage : Colors.transparent,
            border: Border.all(color: done ? c.sage : (due ? (isToday ? c.brass : c.line) : c.sunken), width: 2),
          ),
          child: done ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
        ),
      ),
    ]);
  }
}

class _HabitForm extends StatefulWidget {
  const _HabitForm({required this.api, this.habit, this.initialDays});
  final Api api;
  final Map<String, dynamic>? habit;
  final Set<int>? initialDays;

  @override
  State<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<_HabitForm> {
  late final _title = TextEditingController(text: widget.habit?['title'] as String? ?? '');
  late bool _daily = widget.initialDays == null;
  late final Set<int> _days = {...?widget.initialDays};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      toast(context, 'اكتب اسم العادة', error: true);
      return;
    }
    if (!_daily && _days.isEmpty) {
      toast(context, 'اختر يوماً واحداً على الأقل', error: true);
      return;
    }
    setState(() => _saving = true);
    final body = {'title': _title.text.trim(), 'days': _daily ? 'daily' : (_days.toList()..sort())};
    try {
      if (widget.habit == null) {
        await widget.api.post('/me/habits', body);
      } else {
        await widget.api.patch('/me/habits/${widget.habit!['id']}', body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.habit == null ? 'عادة جديدة' : 'تعديل العادة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'العادة', hintText: 'مثال: قراءة 10 صفحات')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('كل يوم'), value: _daily, onChanged: (v) => setState(() => _daily = v)),
          if (!_daily)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in _weekOrder) FilterChip(label: Text(dayNames[d]), selected: _days.contains(d), onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d))),
            ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ'))),
      ),
    );
  }
}
