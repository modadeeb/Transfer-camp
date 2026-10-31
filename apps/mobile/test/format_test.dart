import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_camp/core/format.dart';
import 'package:transfer_camp/models/models.dart';
import 'package:transfer_camp/widgets/fields.dart';

void main() {
  test('weeks start on Saturday', () {
    expect(weekStartOf('2026-10-31'), '2026-10-31'); // Saturday
    expect(weekStartOf('2026-11-06'), '2026-10-31'); // Friday
    expect(weekStartOf('2026-11-07'), '2026-11-07');
    expect(dayOfWeek('2026-11-01'), 0); // Sunday
  });

  test('money and time formatting', () {
    expect(formatMoney(12500), '12,500 ر.ي');
    expect(formatMoney(-3000), '−3,000 ر.ي');
    expect(formatTime('14:30'), '2:30 م');
    expect(formatTime('00:05'), '12:05 ص');
    expect(formatDuration(390), '6 س 30 د');
  });

  test('Arabic number agreement', () {
    expect(count(1, tasksForms), 'مهمة واحدة');
    expect(count(2, tasksForms), 'مهمتان');
    expect(count(5, tasksForms), '5 مهام');
    expect(count(12, tasksForms), '12 مهمة');
  });

  test('amount parsing accepts Arabic digits and separators', () {
    expect(parseAmount('١٢٬٥٠٠'), 12500);
    expect(parseAmount('12,500'), 12500);
    expect(parseAmount(''), null);
  });

  test('overdue', () {
    final t = Task({'id': 1, 'status': 'pending', 'dueDate': '2026-10-30', 'dueTime': null});
    expect(t.isOverdue('2026-10-31', '10:00'), true);
    final today = Task({'id': 2, 'status': 'pending', 'dueDate': '2026-10-31', 'dueTime': '09:00'});
    expect(today.isOverdue('2026-10-31', '10:00'), true);
    expect(today.isOverdue('2026-10-31', '08:00'), false);
    final done = Task({'id': 3, 'status': 'approved', 'dueDate': '2026-10-01'});
    expect(done.isOverdue('2026-10-31', '10:00'), false);
  });
}
