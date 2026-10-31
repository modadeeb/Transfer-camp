import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (hint != null) Text(hint!, style: TextStyle(fontSize: 12.5, color: context.c.muted)),
        ],
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Picks an Aden calendar date ('YYYY-MM-DD').
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.error, this.clearable = true});

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;
  final bool clearable;

  Future<void> _pick(BuildContext context) async {
    final today = adenDate();
    final current = value ?? today;
    final p = current.split('-').map(int.parse).toList();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(p[0], p[1], p[2]),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      locale: const Locale('ar'),
    );
    if (picked != null) onChanged('${picked.year}-${_two(picked.month)}-${_two(picked.day)}');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: clearable && value != null
              ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value == null ? 'بلا موعد' : formatDate(value, weekday: true), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Picks a time ('HH:MM').
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = true});

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool clearable;

  Future<void> _pick(BuildContext context) async {
    final parts = (value ?? '09:00').split(':').map(int.parse).toList();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: parts[0], minute: parts[1]));
    if (picked != null) onChanged('${_two(picked.hour)}:${_two(picked.minute)}');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && value != null
              ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))
              : const Icon(Icons.schedule_rounded, size: 18),
        ),
        child: Text(value == null ? '—' : formatTime(value), maxLines: 1),
      ),
    );
  }
}

/// − value + control for small integers.
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 100});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(tooltip: 'إنقاص', onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_rounded)),
        Container(
          width: 56,
          alignment: Alignment.center,
          child: Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
        ),
        IconButton.outlined(tooltip: 'زيادة', onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_rounded)),
      ],
    );
  }
}

/// Whole-rial amount input with thousands hint.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.label = 'المبلغ', this.error, this.validator});

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, suffixText: 'ر.ي', errorText: error),
      validator: validator ??
          (v) {
            final n = parseAmount(v);
            return n == null || n <= 0 ? 'اكتب مبلغاً صحيحاً' : null;
          },
    );
  }
}

/// Accepts Latin or Arabic-Indic digits and thousands separators.
int? parseAmount(String? v) {
  if (v == null) return null;
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in v.split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      buf.write(i);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      buf.write(ch);
    }
  }
  final s = buf.toString();
  return s.isEmpty ? null : int.tryParse(s);
}
