import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'common.dart';
import 'fields.dart';

enum FType { text, multiline, date, time, select, amount, integer, toggle, members, member }

/// One field of a [showFormSheet] form. Values: text → String?, date/time → 'YYYY-MM-DD'/'HH:MM'?,
/// select → String?, amount/integer → int?, toggle → bool, members → List<int>, member → int?.
class F {
  const F(this.key, this.label, this.type, {this.initial, this.required = false, this.options = const {}, this.hint, this.min = 1, this.max = 1000000000, this.maxLength});

  final String key;
  final String label;
  final FType type;
  final Object? initial;
  final bool required;
  final Map<String, String> options;
  final String? hint;
  final int min;
  final int max;
  final int? maxLength;
}

/// Bottom-sheet form. [onSubmit] gets the values; throwing an [ApiException] shows its field errors.
/// Returns true when the form was saved.
Future<bool> showFormSheet(
  BuildContext context, {
  required String title,
  required List<F> fields,
  required Future<void> Function(Map<String, dynamic> values) onSubmit,
  String submitLabel = 'حفظ',
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FormSheet(title: title, fields: fields, onSubmit: onSubmit, submitLabel: submitLabel),
  );
  return ok ?? false;
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.title, required this.fields, required this.onSubmit, required this.submitLabel});
  final String title;
  final List<F> fields;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  final String submitLabel;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _form = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _text = {};
  Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.type) {
        case FType.text:
        case FType.multiline:
          _text[f.key] = TextEditingController(text: f.initial as String? ?? '');
        case FType.amount:
        case FType.integer:
          _text[f.key] = TextEditingController(text: f.initial == null ? '' : '${f.initial}');
        case FType.toggle:
          _values[f.key] = f.initial == true;
        case FType.members:
          _values[f.key] = <int>{...(f.initial as Iterable<int>? ?? const <int>[])};
        default:
          _values[f.key] = f.initial;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _collect() {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case FType.text:
        case FType.multiline:
          final v = _text[f.key]!.text.trim();
          out[f.key] = v.isEmpty ? null : v;
        case FType.amount:
        case FType.integer:
          out[f.key] = parseAmount(_text[f.key]!.text);
        case FType.members:
          out[f.key] = (_values[f.key] as Set<int>).toList();
        default:
          out[f.key] = _values[f.key];
      }
    }
    return out;
  }

  Future<void> _submit() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    for (final f in widget.fields) {
      if (f.required && (f.type == FType.date || f.type == FType.select || f.type == FType.member) && _values[f.key] == null) {
        setState(() => _errors = {f.key: 'مطلوب'});
        return;
      }
      if (f.required && f.type == FType.members && (_values[f.key] as Set<int>).isEmpty) {
        setState(() => _errors = {f.key: 'اختر عضواً واحداً على الأقل'});
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_collect());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.fields);
      if (e.fields.isEmpty || !e.fields.keys.any((k) => widget.fields.any((f) => f.key == k))) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final f in widget.fields) ...[_field(f, c), const SizedBox(height: 14)],
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(F f, CampColors c) {
    final error = _errors[f.key];
    switch (f.type) {
      case FType.text:
      case FType.multiline:
        return TextFormField(
          controller: _text[f.key],
          minLines: f.type == FType.multiline ? 2 : 1,
          maxLines: f.type == FType.multiline ? 6 : 1,
          maxLength: f.maxLength,
          decoration: InputDecoration(labelText: f.required ? f.label : '${f.label} (اختياري)', hintText: f.hint, errorText: error),
          validator: f.required ? (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null : null,
        );
      case FType.amount:
        return AmountField(
          controller: _text[f.key]!,
          label: f.label,
          error: error,
          validator: (v) {
            final n = parseAmount(v);
            if (n == null) return f.required ? 'اكتب مبلغاً صحيحاً' : null;
            if (n < f.min) return 'المبلغ أقل من المسموح';
            return null;
          },
        );
      case FType.integer:
        return TextFormField(
          controller: _text[f.key],
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: f.required ? f.label : '${f.label} (اختياري)', hintText: f.hint, errorText: error),
          validator: (v) {
            final n = parseAmount(v);
            if (n == null) return f.required ? 'مطلوب' : null;
            if (n < f.min || n > f.max) return 'من ${f.min} إلى ${f.max}';
            return null;
          },
        );
      case FType.date:
        return DateField(label: f.label, value: _values[f.key] as String?, error: error, clearable: !f.required, onChanged: (v) => setState(() => _values[f.key] = v));
      case FType.time:
        return TimeField(label: f.label, value: _values[f.key] as String?, onChanged: (v) => setState(() => _values[f.key] = v));
      case FType.select:
        return DropdownButtonFormField<String?>(
          value: f.options.containsKey(_values[f.key]) ? _values[f.key] as String? : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label, errorText: error),
          items: [
            if (!f.required) const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final e in f.options.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: f.hint == null ? null : Text(f.hint!),
          value: _values[f.key] as bool,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FType.members:
      case FType.member:
        final members = context.read<Session>().members.where((m) => !m.archived).toList();
        final multi = f.type == FType.members;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(f.label, hint: f.hint),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in members)
                  FilterChip(
                    avatar: Avatar(name: m.name, color: m.color, size: 22),
                    label: Text(m.name),
                    showCheckmark: false,
                    selected: multi ? (_values[f.key] as Set<int>).contains(m.id) : _values[f.key] == m.id,
                    onSelected: (on) => setState(() {
                      if (multi) {
                        final set = _values[f.key] as Set<int>;
                        on ? set.add(m.id) : set.remove(m.id);
                      } else {
                        _values[f.key] = on ? m.id : null;
                      }
                    }),
                  ),
              ],
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error, style: TextStyle(color: c.danger, fontSize: 12))),
          ],
        );
    }
  }
}
