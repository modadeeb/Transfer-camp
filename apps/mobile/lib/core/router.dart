import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/change_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/housing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/me_screen.dart';
import '../screens/money_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shell.dart';
import '../screens/splash_screen.dart';
import '../screens/task_screen.dart';
import '../screens/work_screen.dart';
import 'session.dart';

GoRouter buildRouter(Session session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (session.status) {
        case SessionStatus.loading:
        case SessionStatus.offline:
          return loc == '/splash' ? null : '/splash';
        case SessionStatus.signedOut:
          return loc == '/login' ? null : '/login';
        case SessionStatus.signedIn:
          if (session.mustChangePassword) return loc == '/change-password' ? null : '/change-password';
          if (loc == '/login' || loc == '/splash' || loc == '/change-password') return '/';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/housing', builder: (_, s) => HousingScreen(week: s.uri.queryParameters['week'], tab: s.uri.queryParameters['tab'])),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/work', builder: (_, s) => WorkScreen(tab: s.uri.queryParameters['tab'])),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/money', builder: (_, s) => MoneyScreen(tab: s.uri.queryParameters['tab'])),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/me', builder: (_, s) => MeScreen(tab: s.uri.queryParameters['tab'])),
          ]),
        ],
      ),
      GoRoute(path: '/task/:id', builder: (_, s) => TaskScreen(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/settings', builder: (_, s) => SettingsScreen(tab: s.uri.queryParameters['tab'])),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('الصفحة غير موجودة')),
    ),
  );
}
