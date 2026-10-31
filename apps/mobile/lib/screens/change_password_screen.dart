import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Forced on first sign-in with a temporary password; also reachable from settings.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.voluntary = false});
  final bool voluntary;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  Map<String, String> _fields = {};

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _fields = {});
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().changePassword(_current.text, _next.text);
      if (!mounted) return;
      toast(context, 'تغيّرت كلمة المرور');
      if (widget.voluntary) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _fields = e.fields);
      if (e.fields.isEmpty) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة المرور'),
        automaticallyImplyLeading: widget.voluntary,
        actions: [
          if (!widget.voluntary) TextButton(onPressed: () => context.read<Session>().logout(), child: const Text('خروج')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.voluntary) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.brassSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Text('هذه كلمة مرور مؤقتة من المدير. اختر كلمة مرور خاصة بك قبل المتابعة.'),
                  ),
                  const SizedBox(height: 18),
                ],
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'كلمة المرور الحالية', errorText: _fields['current']),
                  validator: (v) => (v ?? '').isEmpty ? 'مطلوبة' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _next,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'كلمة المرور الجديدة', helperText: '8 أحرف على الأقل', errorText: _fields['password']),
                  validator: (v) => (v ?? '').length < 8 ? '8 أحرف على الأقل' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _again,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'أعد كتابة كلمة المرور الجديدة'),
                  validator: (v) => v != _next.text ? 'غير متطابقة' : null,
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('حفظ كلمة المرور'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
