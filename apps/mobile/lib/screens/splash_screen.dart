import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../core/theme.dart';
import 'login_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final c = context.c;
    final offline = session.status == SessionStatus.offline;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/icon.png', width: 88, height: 88)),
                const SizedBox(height: 18),
                Text(session.campName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 22),
                if (!offline)
                  const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
                else ...[
                  Icon(Icons.wifi_off_rounded, color: c.danger, size: 30),
                  const SizedBox(height: 10),
                  Text(session.error ?? 'تعذّر الاتصال بالخادم', textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: session.restore, child: const Text('إعادة المحاولة')),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => showServerSheet(context), child: const Text('تغيير عنوان الخادم')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
