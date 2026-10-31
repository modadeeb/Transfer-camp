import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

IconData _icon(String type) => switch (type) {
      'task_assigned' || 'task_updated' => Icons.assignment_outlined,
      'task_reminder' => Icons.alarm_rounded,
      'task_overdue' || 'overdue_summary' => Icons.schedule_rounded,
      'task_returned' => Icons.replay_rounded,
      'task_submitted' => Icons.fact_check_outlined,
      'task_approved' => Icons.thumb_up_alt_outlined,
      'task_deleted' => Icons.delete_outline_rounded,
      'swap_request' || 'swap_response' => Icons.swap_horiz_rounded,
      'contribution_due' || 'debt_payment' => Icons.account_balance_wallet_outlined,
      'morning_summary' => Icons.wb_sunny_outlined,
      'distribution' => Icons.event_note_outlined,
      _ => Icons.notifications_none_rounded,
    };

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await api.post('/notifications/read-all');
                if (context.mounted) context.read<RefreshBus>().bump();
              } on ApiException catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('قراءة الكل'),
          ),
        ],
      ),
      body: Loader(
        load: () => api.get('/notifications', {'limit': 100}),
        builder: (context, data, reload) {
          final list = listOf(data['notifications'], AppNotification.new);
          final types = (data['types'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
          if (list.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.notifications_none_rounded, title: 'لا إشعارات', body: 'ستصلك هنا المهام والتذكيرات')]);
          }
          return _List(items: list, types: types);
        },
      ),
    );
  }
}

/// Keeps its own copy so a swiped item leaves the tree immediately.
class _List extends StatefulWidget {
  const _List({required this.items, required this.types});
  final List<AppNotification> items;
  final Map<String, String> types;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  late List<AppNotification> _items = [...widget.items];

  @override
  void didUpdateWidget(covariant _List old) {
    super.didUpdateWidget(old);
    _items = [...widget.items];
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) => _Item(
        n: _items[i],
        typeLabel: widget.types[_items[i].type],
        onDismissed: (n) {
          setState(() => _items.removeWhere((x) => x.id == n.id));
          final api = context.read<Session>().api;
          deleteWithUndo(
            this.context,
            remove: () => api.delete('/notifications/${n.id}'),
            restore: () => api.post('/notifications/${n.id}/restore'),
            message: 'حُذف الإشعار',
          );
        },
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.n, required this.onDismissed, this.typeLabel});
  final AppNotification n;
  final String? typeLabel;
  final ValueChanged<AppNotification> onDismissed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final api = context.read<Session>().api;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: c.dangerSoft,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline_rounded, color: c.danger),
      ),
      onDismissed: (_) => onDismissed(n),
      child: ListTile(
        tileColor: n.read ? null : c.sageSoft.withAlpha(110),
        leading: CircleAvatar(
          backgroundColor: n.urgent ? c.dangerSoft : c.sageSoft,
          child: Icon(_icon(n.type), color: n.urgent ? c.danger : c.forest, size: 20),
        ),
        title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((n.body ?? '').isNotEmpty) Text(n.body!),
            Text([typeLabel, timeAgo(n.createdAt)].where((s) => s != null && s.isNotEmpty).join(' · '), style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        onTap: () async {
          if (!n.read) {
            try {
              await api.post('/notifications/${n.id}/read');
            } on ApiException {
              // opening the link still makes sense
            }
          }
          if (!context.mounted) return;
          final link = n.link;
          if (link != null && link.startsWith('/')) {
            context.read<RefreshBus>().bump();
            if (link.startsWith('/task/')) {
              context.push(link);
            } else {
              context.go(link);
            }
          } else {
            context.read<RefreshBus>().bump();
          }
        },
      ),
    );
  }
}
