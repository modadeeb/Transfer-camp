import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Lets one screen tell the others that data changed (like ui.bump in the web app).
class RefreshBus extends ChangeNotifier {
  int version = 0;
  void bump() {
    version += 1;
    notifyListeners();
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = context.c;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? c.danger : null,
      duration: Duration(milliseconds: error ? 4500 : 2800),
    ));
}

void showError(BuildContext context, Object e) {
  toast(context, e is ApiException ? e.message : 'حدث خطأ غير متوقع', error: true);
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? body, String confirmLabel = 'تأكيد', bool danger = false}) async {
  final c = context.c;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: body == null ? null : Text(body, style: TextStyle(color: c.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a short text (e.g. the reason for returning a task). Returns null when cancelled.
Future<String?> promptText(BuildContext context, {required String title, required String label, String? hint, String confirmLabel = 'حفظ', int maxLength = 1000}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: TextStyle(color: ctx.c.muted)),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: maxLength,
              decoration: InputDecoration(labelText: label),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: c.muted)),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: c.sageSoft, shape: BoxShape.circle),
            child: Icon(icon, color: c.sage),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(body!, textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.color, this.size = 32});

  final String name;
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = parseColor(color, context.c.forest);
    final letter = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600, height: 1.1)),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.fg, required this.bg, this.icon});

  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Loads data, shows loading / error-with-retry, supports pull to refresh,
/// and reloads whenever the [RefreshBus] is bumped.
class Loader extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload) builder;

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;
  RefreshBus? _bus;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bus = context.read<RefreshBus>();
    if (_bus != bus) {
      _bus?.removeListener(_onBus);
      _bus = bus..addListener(_onBus);
      _seen = bus.version;
    }
  }

  @override
  void dispose() {
    _bus?.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (_bus!.version != _seen) {
      _seen = _bus!.version;
      _reload();
    }
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = _data == null);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_data != null) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'تعذّر التحميل',
            body: _error is ApiException ? (_error as ApiException).message : 'حدث خطأ غير متوقع',
            action: FilledButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
          ),
        ],
      );
    }
    return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, _data!, _reload));
  }
}

class SheetAction {
  const SheetAction(this.key, this.label, this.icon, {this.danger = false});
  final String key;
  final String label;
  final IconData icon;
  final bool danger;
}

/// Bottom sheet of actions (view / edit / copy / archive / delete …). Returns the chosen key.
Future<String?> showActions(BuildContext context, {String? title, required List<SheetAction> actions}) {
  final c = context.c;
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.danger ? c.danger : c.forest),
              title: Text(a.label, style: TextStyle(color: a.danger ? c.danger : null)),
              onTap: () => Navigator.pop(ctx, a.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Soft delete with a 5-second undo, like the web app.
Future<void> deleteWithUndo(
  BuildContext context, {
  required Future<void> Function() remove,
  Future<void> Function()? restore,
  String message = 'حُذف',
}) async {
  try {
    await remove();
  } on ApiException catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final bus = context.read<RefreshBus>()..bump();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: restore == null
          ? null
          : SnackBarAction(
              label: 'تراجع',
              onPressed: () async {
                try {
                  await restore();
                  bus.bump();
                } catch (_) {
                  // nothing to show once the snackbar is gone
                }
              },
            ),
    ));
}
