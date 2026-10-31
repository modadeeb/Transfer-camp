import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_user.text, _pass.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final c = context.c;
    final notice = _error ?? session.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/icon.png', width: 72, height: 72))),
                    const SizedBox(height: 16),
                    Text(session.campName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('سجّل الدخول بحسابك', textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _user,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline_rounded)),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب اسم المستخدم' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pass,
                      obscureText: _hide,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'إظهار' : 'إخفاء',
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) => (v ?? '').isEmpty ? 'اكتب كلمة المرور' : null,
                    ),
                    if (notice != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(10)),
                        child: Text(notice, style: TextStyle(color: c.danger)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('دخول'),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: () => showServerSheet(context),
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: Text('الخادم: ${Uri.tryParse(session.api.server)?.host ?? session.api.server}', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user point the app at another address (e.g. after moving to a custom domain).
Future<void> showServerSheet(BuildContext context) async {
  final session = context.read<Session>();
  final controller = TextEditingController(text: session.api.server);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('عنوان الخادم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('غيّره فقط إذا طلب منك المدير ذلك.', style: TextStyle(color: ctx.c.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://camp.example.com'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          TextButton(
            onPressed: () {
              controller.text = kDefaultServer;
              Navigator.pop(ctx, true);
            },
            child: const Text('الرجوع للعنوان الافتراضي'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  await session.api.setServer(controller.text);
  await session.api.clearSession();
  await session.restore();
  if (context.mounted) toast(context, 'حُفظ عنوان الخادم');
}
