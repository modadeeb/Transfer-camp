import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Unread notification count, refreshed periodically, on resume and when data changes.
class Unread extends ChangeNotifier with WidgetsBindingObserver {
  Unread(this.session, this.bus) {
    WidgetsBinding.instance.addObserver(this);
    bus.addListener(refresh);
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => refresh());
    refresh();
  }

  final Session session;
  final RefreshBus bus;
  Timer? _timer;
  int count = 0;

  Future<void> refresh() async {
    if (session.status != SessionStatus.signedIn) return;
    try {
      final r = await session.api.get('/notifications', {'limit': 1});
      final n = r['unread'];
      if (n is int && n != count) {
        count = n;
        notifyListeners();
      }
    } catch (_) {
      // keep the last known count
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      bus.bump();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    bus.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.dashboard_outlined, Icons.dashboard_rounded, 'الرئيسية'),
    (Icons.home_outlined, Icons.home_rounded, 'السكن'),
    (Icons.work_outline_rounded, Icons.work_rounded, 'العمل'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'المال'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'أنا'),
  ];

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => Unread(ctx.read<Session>(), ctx.read<RefreshBus>()),
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
          ],
        ),
      ),
    );
  }
}

/// Top bar used by the five main tabs: title, bell with unread badge, settings.
class CampAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CampAppBar({super.key, required this.title, this.bottom, this.actions = const []});

  final String title;
  final PreferredSizeWidget? bottom;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<Unread>().count;
    final c = context.c;
    return AppBar(
      title: Text(title),
      bottom: bottom,
      actions: [
        ...actions,
        IconButton(
          tooltip: 'الإشعارات',
          onPressed: () async {
            await context.push('/notifications');
            if (context.mounted) context.read<Unread>().refresh();
          },
          icon: Badge(
            isLabelVisible: unread > 0,
            backgroundColor: c.brass,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        IconButton(tooltip: 'الإعدادات', onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
        const SizedBox(width: 4),
      ],
    );
  }
}
