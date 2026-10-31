import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

const prayerNames = {'fajr': 'الفجر', 'dhuhr': 'الظهر', 'asr': 'العصر', 'maghrib': 'المغرب', 'isha': 'العشاء'};

/// Five round checks with times; the next prayer is highlighted (times come from the API).
class PrayerRow extends StatelessWidget {
  const PrayerRow({super.key, required this.times, required this.done, required this.onToggle, this.now, this.enabled = true});

  final Map<String, String> times;
  final Set<String> done;
  final void Function(String key) onToggle;
  final String? now;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    String? next;
    if (now != null) {
      for (final k in prayerNames.keys) {
        final t = times[k];
        if (t != null && t.compareTo(now!) > 0) {
          next = k;
          break;
        }
      }
    }
    return Row(
      children: [
        for (final e in prayerNames.entries)
          Expanded(
            child: Semantics(
              checked: done.contains(e.key),
              label: '${e.value} ${formatTime(times[e.key])}',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: enabled ? () => onToggle(e.key) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: next == e.key && !done.contains(e.key) ? c.brassSoft : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done.contains(e.key) ? c.sage : Colors.transparent,
                          border: Border.all(color: done.contains(e.key) ? c.sage : (next == e.key ? c.brass : c.line), width: 2),
                        ),
                        child: done.contains(e.key) ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(
                        formatTime(times[e.key]),
                        style: TextStyle(fontSize: 11, color: next == e.key ? c.brass : c.muted, fontWeight: next == e.key ? FontWeight.w600 : FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
