import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import 'shell.dart';

const expenseCategories = {
  'rent': 'إيجار',
  'electricity': 'كهرباء',
  'water': 'ماء',
  'internet': 'إنترنت',
  'groceries': 'مشتريات المطبخ',
  'cleaning': 'منظفات',
  'gas': 'غاز',
  'maintenance': 'صيانة',
  'other': 'أخرى',
};

List<Map<String, dynamic>> _maps(Object? v) => (v is List ? v : const []).whereType<Map<String, dynamic>>().toList();

class MoneyScreen extends StatelessWidget {
  const MoneyScreen({super.key, this.tab});
  final String? tab;

  @override
  Widget build(BuildContext context) {
    const tabs = [('fund', 'الصندوق'), ('expenses', 'المصاريف'), ('balances', 'الأرصدة'), ('debts', 'الديون')];
    final initial = tabs.indexWhere((t) => t.$1 == tab);
    return DefaultTabController(
      key: ValueKey('money-$tab'),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: CampAppBar(
          title: 'المال',
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$2)]),
        ),
        body: const TabBarView(children: [_Fund(), _Expenses(), _Balances(), _Debts()]),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, this.color, this.sub});
  final String label;
  final num value;
  final Color? color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
        Text(formatMoney(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color ?? c.forest)),
        if (sub != null) Text(sub!, style: TextStyle(color: c.muted, fontSize: 12.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------- fund

class _Fund extends StatelessWidget {
  const _Fund();

  Future<void> _newPeriod(BuildContext context) async {
    final api = context.read<Session>().api;
    final now = adenDate();
    final saved = await showFormSheet(
      context,
      title: 'مساهمة جديدة',
      fields: [
        F('title', 'العنوان', FType.text, required: true, initial: formatMonth(addDays(now, 5)), maxLength: 60),
        const F('amountPerMember', 'حصة كل عضو', FType.amount, required: true, min: 0),
        F('dueDate', 'آخر موعد', FType.date, initial: addDays(now, 7)),
        const F('memberIds', 'الأعضاء', FType.members, hint: 'اتركها فارغة لتشمل كل الأعضاء'),
      ],
      onSubmit: (v) => api.post('/contribution-periods', v),
    );
    if (saved && context.mounted) {
      toast(context, 'أُضيفت المساهمة وأُرسل إشعار للأعضاء');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _payment(BuildContext context, Map<String, dynamic> row) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: 'تسجيل دفعة من ${row['userName']}',
      fields: [
        F('amount', 'المبلغ', FType.amount, required: true, initial: row['remaining']),
        F('date', 'التاريخ', FType.date, required: true, initial: adenDate()),
        const F('note', 'ملاحظة', FType.text, maxLength: 200),
      ],
      onSubmit: (v) => api.post('/contributions/${row['id']}/payments', v),
    );
    if (saved && context.mounted) {
      toast(context, 'سُجّلت الدفعة');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _periodActions(BuildContext context, Map<String, dynamic> p) async {
    final api = context.read<Session>().api;
    final key = await showActions(context, title: '${p['title']}', actions: const [
      SheetAction('edit', 'تعديل', Icons.edit_outlined),
      SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    if (key == 'edit') {
      final saved = await showFormSheet(
        context,
        title: 'تعديل المساهمة',
        fields: [
          F('title', 'العنوان', FType.text, required: true, initial: p['title'], maxLength: 60),
          F('dueDate', 'آخر موعد', FType.date, initial: p['dueDate']),
        ],
        onSubmit: (v) => api.patch('/contribution-periods/${p['id']}', v),
      );
      if (saved && context.mounted) context.read<RefreshBus>().bump();
    } else {
      final ok = await confirmDialog(context, title: 'حذف المساهمة؟', body: 'تُحذف معها دفعاتها من حساب الصندوق.', confirmLabel: 'حذف', danger: true);
      if (!ok || !context.mounted) return;
      await deleteWithUndo(
        context,
        remove: () => api.delete('/contribution-periods/${p['id']}'),
        restore: () => api.post('/contribution-periods/${p['id']}/restore'),
        message: 'حُذفت المساهمة',
      );
    }
  }

  Future<void> _rowActions(BuildContext context, Map<String, dynamic> row) async {
    final api = context.read<Session>().api;
    final key = await showActions(context, title: '${row['userName']}', actions: [
      if (((row['remaining'] as num?) ?? 0) > 0) const SheetAction('pay', 'تسجيل دفعة', Icons.payments_outlined),
      if (((row['remaining'] as num?) ?? 0) > 0) const SheetAction('remind', 'تذكير', Icons.notifications_active_outlined),
      const SheetAction('due', 'تعديل الحصة', Icons.edit_outlined),
      const SheetAction('payments', 'الدفعات', Icons.receipt_long_outlined),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'pay':
          await _payment(context, row);
        case 'remind':
          await api.post('/contributions/${row['id']}/remind');
          if (context.mounted) toast(context, 'أُرسل التذكير');
        case 'due':
          final saved = await showFormSheet(
            context,
            title: 'حصة ${row['userName']}',
            fields: [F('amountDue', 'الحصة', FType.amount, required: true, initial: row['amountDue'], min: 0)],
            onSubmit: (v) => api.patch('/contributions/${row['id']}', v),
          );
          if (saved && context.mounted) context.read<RefreshBus>().bump();
        case 'payments':
          await _showPayments(context, row);
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _showPayments(BuildContext context, Map<String, dynamic> row) async {
    final api = context.read<Session>().api;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Loader(
          load: () => api.get('/contributions/${row['id']}/payments'),
          builder: (ctx, data, reload) {
            final list = _maps(data['payments']);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text('دفعات ${row['userName']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (list.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا دفعات'),
                for (final p in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatMoney(p['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${formatDate(p['date'] as String?, weekday: true)}${p['note'] != null ? ' · ${p['note']}' : ''}'),
                    trailing: IconButton(
                      tooltip: 'حذف الدفعة',
                      icon: Icon(Icons.delete_outline_rounded, color: ctx.c.danger),
                      onPressed: () async {
                        final ok = await confirmDialog(ctx, title: 'حذف الدفعة؟', confirmLabel: 'حذف', danger: true);
                        if (!ok) return;
                        try {
                          await api.delete('/contribution-payments/${p['id']}');
                          await reload();
                          if (context.mounted) context.read<RefreshBus>().bump();
                        } on ApiException catch (e) {
                          if (ctx.mounted) showError(ctx, e);
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    return Loader(
      load: () => session.api.get('/fund'),
      builder: (context, data, reload) {
        final fund = data['fund'] as Map? ?? const {};
        final periods = _maps(data['periods']);
        final me = data['me'] as Map? ?? const {};
        final myDues = _maps(me['contributionsDue']);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: _Big(label: 'رصيد الصندوق', value: (fund['balance'] as num?) ?? 0)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('دخل ${formatMoney(fund['inflow'] as num?)}', style: TextStyle(color: c.sage, fontSize: 13)),
                        Text('صُرف ${formatMoney(fund['outflow'] as num?)}', style: TextStyle(color: c.danger, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            for (final d in myDues) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.brassSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('عليك لمساهمة ${d['title']}: ${formatMoney(d['remaining'] as num?)}', style: TextStyle(color: c.brass, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 12),
            if (session.isManager)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => _newPeriod(context), icon: const Icon(Icons.add_rounded), label: const Text('مساهمة جديدة')),
              ),
            if (periods.isEmpty) const EmptyState(icon: Icons.savings_outlined, title: 'لا مساهمات بعد'),
            for (final p in periods) ...[
              const SizedBox(height: 10),
              SectionCard(
                title: '${p['title']}',
                subtitle: 'الحصة ${formatMoney(p['amountPerMember'] as num?)}${p['dueDate'] != null ? ' · حتى ${formatDate(p['dueDate'] as String?)}' : ''}',
                trailing: session.isManager ? IconButton(tooltip: 'خيارات', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _periodActions(context, p)) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ((p['totalDue'] as num?) ?? 0) == 0 ? 0 : ((p['totalPaid'] as num?) ?? 0) / (p['totalDue'] as num),
                        minHeight: 8,
                        backgroundColor: c.sunken,
                        color: c.sage,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('جُمع ${formatMoney(p['totalPaid'] as num?)} من ${formatMoney(p['totalDue'] as num?)}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    for (final row in _maps(p['contributions']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: session.isManager ? () => _rowActions(context, row) : null,
                        leading: Avatar(name: '${row['userName']}', color: row['userColor'] as String?, size: 28),
                        title: Text('${row['userName']}'),
                        trailing: switch (row['status']) {
                          'paid' => Pill('مدفوعة', fg: c.sage, bg: c.sageSoft),
                          'partial' => Pill('باقي ${formatMoney(row['remaining'] as num?)}', fg: c.brass, bg: c.brassSoft),
                          _ => Pill('لم تُدفع', fg: c.danger, bg: c.dangerSoft),
                        },
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

// ---------------------------------------------------------------- shared expenses

class _Expenses extends StatelessWidget {
  const _Expenses();

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? e]) async {
    final session = context.read<Session>();
    final api = session.api;
    final split = ((e?['splitMemberIds'] as List?) ?? session.members.where((m) => !m.archived).map((m) => m.id)).whereType<int>();
    final saved = await showFormSheet(
      context,
      title: e == null ? 'مصروف مشترك' : 'تعديل المصروف',
      fields: [
        F('title', 'البيان', FType.text, required: true, initial: e?['title'], maxLength: 100, hint: 'مثال: خضار وفواكه'),
        F('amount', 'المبلغ', FType.amount, required: true, initial: e?['amount']),
        F('category', 'التصنيف', FType.select, required: true, options: expenseCategories, initial: e?['category'] ?? 'groceries'),
        F('date', 'التاريخ', FType.date, required: true, initial: e?['date'] ?? adenDate()),
        if (session.isManager) F('paidFromFund', 'دُفع من الصندوق', FType.toggle, initial: e?['paidFromFund'] == true),
        F('payerId', 'من دفع؟', FType.member, initial: e?['payerId'] ?? session.user?.id, hint: 'إن لم يُدفع من الصندوق'),
        F('splitMemberIds', 'يُقسم على', FType.members, initial: split),
        F('note', 'ملاحظة', FType.multiline, initial: e?['note'], maxLength: 500),
      ],
      onSubmit: (v) async {
        if (v['paidFromFund'] == true) v['payerId'] = null;
        if (e == null) {
          await api.post('/shared-expenses', v);
        } else {
          await api.patch('/shared-expenses/${e['id']}', v);
        }
      },
    );
    if (saved && context.mounted) {
      toast(context, e == null ? 'أُضيف المصروف' : 'حُفظ المصروف');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> e) async {
    final api = context.read<Session>().api;
    final key = await showActions(context, title: '${e['title']} · ${formatMoney(e['amount'] as num?)}', actions: const [
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
          await api.post('/shared-expenses/${e['id']}/copy');
          if (context.mounted) {
            toast(context, 'نُسخ المصروف بتاريخ اليوم');
            context.read<RefreshBus>().bump();
          }
        case 'delete':
          await deleteWithUndo(
            context,
            remove: () => api.delete('/shared-expenses/${e['id']}'),
            restore: () => api.post('/shared-expenses/${e['id']}/restore'),
            message: 'حُذف المصروف',
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
    final me = session.user?.id;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expense-fab',
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('مصروف'),
      ),
      body: Loader(
        load: () => session.api.get('/shared-expenses'),
        builder: (context, data, reload) {
          final list = _maps(data['expenses']);
          if (list.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.receipt_long_outlined, title: 'لا مصاريف بعد', body: 'سجّل ما تشتريه للسكن ليُقسم بالعدل')]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = list[i];
              final canEdit = session.isManager || e['createdBy'] == me;
              final share = (e['shares'] as Map?)?['$me'];
              return Card(
                child: ListTile(
                  onTap: canEdit ? () => _actions(context, e) : null,
                  leading: CircleAvatar(backgroundColor: c.sageSoft, child: Icon(Icons.shopping_basket_outlined, color: c.sage, size: 20)),
                  title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    expenseCategories[e['category']] ?? '',
                    relativeDay(e['date'] as String?),
                    e['paidFromFund'] == true ? 'من الصندوق' : 'دفع ${e['payerName'] ?? '—'}',
                    if (share != null) 'حصتك ${formatMoney(share as num)}',
                  ].join(' · ')),
                  trailing: Text(formatMoney(e['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- balances & settlements

class _Balances extends StatelessWidget {
  const _Balances();

  Future<void> _settle(BuildContext context, {int? toId, num? amount}) async {
    final session = context.read<Session>();
    final saved = await showFormSheet(
      context,
      title: 'تسجيل تسوية',
      submitLabel: 'تسجيل',
      fields: [
        if (session.isManager) F('fromUserId', 'من دفع؟', FType.member, initial: session.user?.id),
        F('toUserId', 'إلى', FType.member, required: true, initial: toId),
        F('amount', 'المبلغ', FType.amount, required: true, initial: amount),
        F('date', 'التاريخ', FType.date, required: true, initial: adenDate()),
        const F('note', 'ملاحظة', FType.text, maxLength: 200),
      ],
      onSubmit: (v) => session.api.post('/settlements', v),
    );
    if (saved && context.mounted) {
      toast(context, 'سُجّلت التسوية');
      context.read<RefreshBus>().bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    return Loader(
      load: () async {
        final fund = await session.api.get('/fund');
        final settlements = await session.api.get('/settlements');
        return {...fund, 'settlements': settlements['settlements']};
      },
      builder: (context, data, reload) {
        final me = data['me'] as Map? ?? const {};
        final net = (me['net'] as num?) ?? 0;
        final members = _maps(data['members']);
        final plan = _maps(data['plan']);
        final settlements = _maps(data['settlements']);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _Big(
                  label: net >= 0 ? 'لك عند المجموعة' : 'عليك للمجموعة',
                  value: net.abs(),
                  color: net >= 0 ? c.sage : c.danger,
                  sub: 'من المصاريف المشتركة والتسويات',
                ),
              ),
            ),
            for (final o in _maps(me['iOwe'])) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text('ادفع لـ${o['name']}'),
                  subtitle: Text(formatMoney(o['amount'] as num?)),
                  trailing: FilledButton(onPressed: () => _settle(context, toId: o['toId'] as int?, amount: o['amount'] as num?), child: const Text('سدّدت')),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionCard(
              title: 'أرصدة الأعضاء',
              child: Column(
                children: [
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Avatar(name: '${m['name']}', color: m['color'] as String?, size: 26),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${m['name']}')),
                        Text(
                          '${((m['net'] as num?) ?? 0) > 0 ? '+' : ''}${formatMoney(m['net'] as num?)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: ((m['net'] as num?) ?? 0) < 0 ? c.danger : c.sage),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            if (plan.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: 'أقصر طريق للتسوية',
                child: Column(
                  children: [
                    for (final p in plan)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text('${p['fromName']} ← ${p['toName']}')),
                          Text(formatMoney(p['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionCard(
              title: 'التسويات',
              trailing: TextButton(onPressed: () => _settle(context), child: const Text('تسجيل')),
              child: settlements.isEmpty
                  ? Text('لا تسويات بعد', style: TextStyle(color: c.muted))
                  : Column(
                      children: [
                        for (final s in settlements.take(30))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${s['fromName']} ← ${s['toName']}'),
                            subtitle: Text('${formatDate(s['date'] as String?, weekday: true)}${s['note'] != null ? ' · ${s['note']}' : ''}'),
                            trailing: Text(formatMoney(s['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
                            onLongPress: (session.isManager || s['createdBy'] == session.user?.id)
                                ? () async {
                                    final ok = await confirmDialog(context, title: 'حذف التسوية؟', confirmLabel: 'حذف', danger: true);
                                    if (!ok || !context.mounted) return;
                                    await deleteWithUndo(
                                      context,
                                      remove: () => session.api.delete('/settlements/${s['id']}'),
                                      message: 'حُذفت التسوية',
                                    );
                                  }
                                : null,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- debts between members

class _Debts extends StatelessWidget {
  const _Debts();

  Future<void> _add(BuildContext context) async {
    final api = context.read<Session>().api;
    final saved = await showFormSheet(
      context,
      title: 'دين جديد',
      fields: [
        const F('direction', 'النوع', FType.select, required: true, options: {'owed': 'أقرضتُ زميلاً (لي)', 'owe': 'اقترضتُ من زميل (عليّ)'}, initial: 'owed'),
        const F('otherUserId', 'الزميل', FType.member, required: true),
        const F('amount', 'المبلغ', FType.amount, required: true),
        const F('title', 'البيان', FType.text, maxLength: 100, hint: 'مثال: سلفة'),
        const F('dueDate', 'موعد السداد', FType.date),
        const F('note', 'ملاحظة', FType.multiline, maxLength: 500),
      ],
      onSubmit: (v) => api.post('/debts', v),
    );
    if (saved && context.mounted) {
      toast(context, 'سُجّل الدين');
      context.read<RefreshBus>().bump();
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> d) async {
    final api = context.read<Session>().api;
    final open = ((d['remaining'] as num?) ?? 0) > 0;
    final key = await showActions(context, title: '${d['title'] ?? 'دين'} · ${formatMoney(d['amount'] as num?)}', actions: [
      if (open) const SheetAction('pay', 'تسجيل سداد', Icons.payments_outlined),
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    switch (key) {
      case 'pay':
        final saved = await showFormSheet(
          context,
          title: 'سداد',
          fields: [
            F('amount', 'المبلغ', FType.amount, required: true, initial: d['remaining']),
            F('date', 'التاريخ', FType.date, required: true, initial: adenDate()),
            const F('note', 'ملاحظة', FType.text, maxLength: 200),
          ],
          onSubmit: (v) => api.post('/debts/${d['id']}/payments', v),
        );
        if (saved && context.mounted) {
          toast(context, 'سُجّل السداد');
          context.read<RefreshBus>().bump();
        }
      case 'edit':
        final edited = await showFormSheet(
          context,
          title: 'تعديل الدين',
          fields: [
            F('title', 'البيان', FType.text, initial: d['title'], maxLength: 100),
            F('dueDate', 'موعد السداد', FType.date, initial: d['dueDate']),
            F('note', 'ملاحظة', FType.multiline, initial: d['note'], maxLength: 500),
          ],
          onSubmit: (v) => api.patch('/debts/${d['id']}', v),
        );
        if (edited && context.mounted) context.read<RefreshBus>().bump();
      case 'delete':
        await deleteWithUndo(
          context,
          remove: () => api.delete('/debts/${d['id']}'),
          restore: () => api.post('/trash/restore', {'entity': 'debt', 'id': d['id']}),
          message: 'حُذف الدين',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final c = context.c;
    final me = session.user?.id;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(heroTag: 'debt-fab', onPressed: () => _add(context), icon: const Icon(Icons.add_rounded), label: const Text('دين')),
      body: Loader(
        load: () => session.api.get('/debts'),
        builder: (context, data, reload) {
          final list = _maps(data['debts']);
          final open = list.where((d) => ((d['remaining'] as num?) ?? 0) > 0).toList();
          final closed = list.where((d) => ((d['remaining'] as num?) ?? 0) <= 0).toList();
          num owedToMe = 0;
          num iOwe = 0;
          for (final d in open) {
            if (d['creditorId'] == me) owedToMe += (d['remaining'] as num?) ?? 0;
            if (d['debtorId'] == me) iOwe += (d['remaining'] as num?) ?? 0;
          }
          Widget tile(Map<String, dynamic> d) {
            final mine = d['creditorId'] == me;
            final party = d['creditorId'] == me || d['debtorId'] == me;
            return Card(
              child: ListTile(
                onTap: party || session.isManager ? () => _actions(context, d) : null,
                title: Text('${d['debtorName']} ← ${d['creditorName']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (d['title'] != null) '${d['title']}',
                  'سُدّد ${formatMoney(d['paid'] as num?)} من ${formatMoney(d['amount'] as num?)}',
                  if (d['dueDate'] != null) 'حتى ${formatDate(d['dueDate'] as String?)}',
                ].join(' · ')),
                trailing: Text(
                  formatMoney(d['remaining'] as num?),
                  style: TextStyle(fontWeight: FontWeight.w700, color: !party ? null : (mine ? c.sage : c.danger)),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Row(children: [
                Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: _Big(label: 'لي عند الزملاء', value: owedToMe, color: c.sage)))),
                const SizedBox(width: 10),
                Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: _Big(label: 'عليّ للزملاء', value: iOwe, color: c.danger)))),
              ]),
              const SizedBox(height: 12),
              if (list.isEmpty) const EmptyState(icon: Icons.handshake_outlined, title: 'لا ديون مسجّلة'),
              for (final d in open) ...[tile(d), const SizedBox(height: 8)],
              if (closed.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 8), child: Text('مسدَّدة', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600))),
                for (final d in closed) ...[tile(d), const SizedBox(height: 8)],
              ],
            ],
          );
        },
      ),
    );
  }
}
