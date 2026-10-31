import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/prayers.dart';
import '../widgets/tasks.dart';
import 'shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: CampAppBar(title: session.campName),
      body: Loader(
        load: () => session.api.get('/home'),
        builder: (context, data, reload) => _HomeBody(data: data, reload: reload),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data, required this.reload});
  final Map<String, dynamic> data;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    final today = '${data['today']}';
    final now = '${data['nowTime']}';
    final tasks = listOf(data['tasks'], Task.new);
    final events = (data['events'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    final swaps = (data['swaps'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    final dues = (data['contributionsDue'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    final manager = data['manager'] is Map<String, dynamic> ? data['manager'] as Map<String, dynamic> : null;
    final times = (data['prayerTimes'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    final prayers = (data['prayers'] as List? ?? const []).map((e) => '$e').toSet();
    final open = tasks.where((t) => !t.isDone).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text('${greeting(now)}، ${session.user?.name.split(' ').first ?? ''}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(formatDate(today, weekday: true, year: true), style: TextStyle(color: c.muted)),
        const SizedBox(height: 16),
        if (manager != null) ..._managerAlerts(context, manager),
        for (final s in swaps) ...[_SwapCard(swap: s), const SizedBox(height: 10)],
        for (final d in dues) ...[
          _Alert(
            icon: Icons.account_balance_wallet_outlined,
            color: d['overdue'] == true ? c.danger : c.brass,
            bg: d['overdue'] == true ? c.dangerSoft : c.brassSoft,
            text: 'مساهمة ${d['title']}: المتبقي ${formatMoney(d['remaining'] as num?)}${d['overdue'] == true ? ' — متأخرة' : ''}',
            onTap: () => context.go('/money'),
          ),
          const SizedBox(height: 10),
        ],
        SectionCard(
          title: 'مهامي اليوم',
          subtitle: tasks.isEmpty ? null : (open == 0 ? 'أنجزت كل شيء 👏' : 'باقي ${count(open, tasksForms)}'),
          trailing: TextButton(onPressed: () => context.go('/work'), child: const Text('كل المهام')),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: tasks.isEmpty
              ? const EmptyState(icon: Icons.task_alt_rounded, title: 'لا مهام اليوم', body: 'استمتع بيومك')
              : Padding(padding: const EdgeInsets.only(bottom: 8), child: TaskList(tasks, today: today, nowTime: now)),
        ),
        if (events.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'اليوم في الفريق',
            child: Column(
              children: [
                for (final e in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(e['kind'] == 'deadline' ? Icons.flag_outlined : Icons.groups_2_outlined, color: c.forest),
                    title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: e['startTime'] == null ? null : Text('${formatTime(e['startTime'] as String?)}${e['endTime'] != null ? ' – ${formatTime(e['endTime'] as String?)}' : ''}'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        SectionCard(
          title: 'الصلوات',
          trailing: Text('${prayers.length} / 5', style: TextStyle(color: c.muted)),
          child: _HomePrayers(today: today, now: now, times: times, initial: prayers),
        ),
        const SizedBox(height: 14),
        _Stats(data: data),
        if (data['budget'] is Map) ...[
          const SizedBox(height: 14),
          _BudgetCard(budget: data['budget'] as Map<String, dynamic>),
        ],
      ],
    );
  }

  List<Widget> _managerAlerts(BuildContext context, Map<String, dynamic> m) {
    final c = context.c;
    final out = <Widget>[];
    void add(IconData icon, String text, String link, {bool danger = false}) {
      out
        ..add(_Alert(icon: icon, text: text, color: danger ? c.danger : c.brass, bg: danger ? c.dangerSoft : c.brassSoft, onTap: () => context.go(link)))
        ..add(const SizedBox(height: 10));
    }

    final pending = (m['pendingApprovals'] as num?) ?? 0;
    final overdue = (m['overdue'] as num?) ?? 0;
    final swaps = (m['pendingSwaps'] as num?) ?? 0;
    if (pending > 0) add(Icons.fact_check_outlined, '${count(pending, tasksForms)} بانتظار اعتمادك', '/work?tab=approvals');
    if (overdue > 0) add(Icons.schedule_rounded, '${count(overdue, tasksForms)} متأخرة', '/work?tab=manage', danger: true);
    if (m['thisWeekDistribution'] == null) add(Icons.event_note_outlined, 'لم يُنشر توزيع مهام السكن لهذا الأسبوع', '/housing?tab=distribution');
    if (m['nextWeekDistribution'] == 'draft') add(Icons.edit_calendar_outlined, 'مسودة توزيع الأسبوع القادم جاهزة للمراجعة', '/housing?tab=distribution&week=${addDays('${data['weekStart']}', 7)}');
    if (swaps > 0) add(Icons.swap_horiz_rounded, 'طلبات تبديل معلّقة: $swaps', '/housing?tab=swaps');
    return out;
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.icon, required this.text, required this.color, required this.bg, this.onTap});
  final IconData icon;
  final String text;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              if (onTap != null) Icon(Icons.chevron_left_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapCard extends StatefulWidget {
  const _SwapCard({required this.swap});
  final Map<String, dynamic> swap;

  @override
  State<_SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends State<_SwapCard> {
  bool _busy = false;

  Future<void> _decide(String decision) async {
    setState(() => _busy = true);
    try {
      await context.read<Session>().api.post('/swaps/${widget.swap['id']}/$decision');
      if (!mounted) return;
      toast(context, decision == 'accept' ? 'قبلت التبديل' : 'رفضت التبديل');
      context.read<RefreshBus>().bump();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.swap;
    final c = context.c;
    return SectionCard(
      title: 'طلب تبديل من ${s['fromName']}',
      subtitle: '${s['taskTitle']} · ${relativeDay(s['taskDueDate'] as String?)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((s['note'] ?? '').toString().isNotEmpty) ...[
            Text('«${s['note']}»', style: TextStyle(color: c.muted)),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: _busy ? null : () => _decide('accept'), child: const Text('قبول'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _decide('reject'), child: const Text('رفض'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomePrayers extends StatefulWidget {
  const _HomePrayers({required this.today, required this.now, required this.times, required this.initial});
  final String today;
  final String now;
  final Map<String, String> times;
  final Set<String> initial;

  @override
  State<_HomePrayers> createState() => _HomePrayersState();
}

class _HomePrayersState extends State<_HomePrayers> {
  late Set<String> _done = {...widget.initial};

  @override
  void didUpdateWidget(covariant _HomePrayers old) {
    super.didUpdateWidget(old);
    if (old.initial.length != widget.initial.length || !old.initial.containsAll(widget.initial)) _done = {...widget.initial};
  }

  Future<void> _toggle(String key) async {
    final on = !_done.contains(key);
    setState(() => on ? _done.add(key) : _done.remove(key));
    try {
      final r = await context.read<Session>().api.put('/me/prayers', {'date': widget.today, 'prayer': key, 'done': on});
      if (mounted) setState(() => _done = (r['done'] as List? ?? const []).map((e) => '$e').toSet());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => on ? _done.remove(key) : _done.add(key));
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PrayerRow(times: widget.times, done: _done, now: widget.now, onToggle: _toggle);
}

class _Stats extends StatelessWidget {
  const _Stats({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final hp = data['housePoints'] as Map? ?? const {};
    final habits = data['habits'] as Map? ?? const {};
    final sleep = data['sleep'] as Map?;
    String sleepText = 'لم يُسجَّل';
    if (sleep != null) {
      final a = '${sleep['sleptAt']}'.split(':').map(int.parse).toList();
      final b = '${sleep['wokeAt']}'.split(':').map(int.parse).toList();
      var mins = (b[0] * 60 + b[1]) - (a[0] * 60 + a[1]);
      if (mins <= 0) mins += 24 * 60;
      sleepText = formatDuration(mins);
    }
    final tiles = [
      _Tile(Icons.home_work_outlined, 'نقاط السكن', '${hp['done'] ?? 0} / ${hp['pts'] ?? 0}', () => context.go('/housing')),
      _Tile(Icons.repeat_rounded, 'عادات اليوم', '${habits['done'] ?? 0} / ${habits['due'] ?? 0}', () => context.go('/me?tab=habits')),
      _Tile(Icons.fitness_center_rounded, 'تمارين الأسبوع', '${data['workoutsThisWeek'] ?? 0}', () => context.go('/me?tab=health')),
      _Tile(Icons.bedtime_outlined, 'نوم الليلة', sleepText, () => context.go('/me?tab=health')),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: tiles,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.value, this.onTap);
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: c.sage),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget});
  final Map<String, dynamic> budget;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = budget['summary'] as Map? ?? const {};
    final left = (s['leftToday'] as num?) ?? 0;
    return SectionCard(
      title: 'ميزانيتي اليوم',
      trailing: TextButton(onPressed: () => context.go('/me?tab=budget'), child: const Text('التفاصيل')),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المتبقي لك اليوم', style: TextStyle(color: c.muted, fontSize: 13)),
                Text(formatMoney(left), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: left < 0 ? c.danger : c.forest)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('المسموح ${formatMoney(s['allowedToday'] as num?)}', style: TextStyle(color: c.muted, fontSize: 13)),
              Text('صرفت ${formatMoney(s['spentToday'] as num?)}', style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}
