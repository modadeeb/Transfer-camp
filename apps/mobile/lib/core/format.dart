// Dates are 'YYYY-MM-DD' strings in Aden time (UTC+3), like the server (packages/domain/src/dates.js).

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
/// Index 0 = Sunday, like JS getUTCDay().
const dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

DateTime _aden([DateTime? at]) => (at ?? DateTime.now()).toUtc().add(const Duration(hours: 3));

String _pad(int n) => n.toString().padLeft(2, '0');

String adenDate([DateTime? at]) {
  final d = _aden(at);
  return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
}

String adenTime([DateTime? at]) {
  final d = _aden(at);
  return '${_pad(d.hour)}:${_pad(d.minute)}';
}

DateTime _parse(String date) {
  final p = date.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _fmt(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

String addDays(String date, int n) => _fmt(_parse(date).add(Duration(days: n)));

/// 0 = Sunday … 6 = Saturday.
int dayOfWeek(String date) => _parse(date).weekday % 7;

/// The week starts on Saturday.
String weekStartOf(String date) {
  final back = (dayOfWeek(date) + 1) % 7;
  return addDays(date, -back);
}

List<String> weekDates(String weekStart) => List.generate(7, (i) => addDays(weekStart, i));

String formatDate(String? date, {bool weekday = false, bool year = false}) {
  if (date == null || date.isEmpty) return '';
  final d = _parse(date);
  final w = weekday ? '${dayNames[d.weekday % 7]} ' : '';
  return '$w${d.day} ${_months[d.month - 1]}${year ? ' ${d.year}' : ''}';
}

String formatMonth(String date) {
  final d = _parse(date);
  return '${_months[d.month - 1]} ${d.year}';
}

/// 14:30 → 2:30 م
String formatTime(String? time) {
  if (time == null || time.isEmpty) return '';
  final p = time.split(':');
  final h = int.parse(p[0]);
  final m = int.parse(p[1]);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${_pad(m)} ${h < 12 ? 'ص' : 'م'}';
}

String formatMoney(num? amount, {bool unit = true}) {
  final n = (amount ?? 0).round();
  final s = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${n < 0 ? '−' : ''}$s${unit ? ' ر.ي' : ''}';
}

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m د';
  return m == 0 ? '$h س' : '$h س $m د';
}

/// «اليوم»، «غداً»، «أمس» or the formatted date.
String relativeDay(String? date) {
  if (date == null || date.isEmpty) return 'بلا موعد';
  final today = adenDate();
  if (date == today) return 'اليوم';
  if (date == addDays(today, 1)) return 'غداً';
  if (date == addDays(today, -1)) return 'أمس';
  return formatDate(date, weekday: true);
}

String timeAgo(String iso) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final diff = DateTime.now().toUtc().difference(at.toUtc()).inSeconds;
  if (diff < 60) return 'الآن';
  if (diff < 3600) return 'قبل ${diff ~/ 60} د';
  if (diff < 86400) return 'قبل ${diff ~/ 3600} س';
  final days = diff ~/ 86400;
  return days == 1 ? 'أمس' : 'قبل $days أيام';
}

String greeting(String time) {
  final h = int.parse(time.substring(0, 2));
  if (h < 12) return 'صباح الخير';
  if (h < 18) return 'مساء الخير';
  return 'مساء النور';
}

/// Arabic number agreement: count(1, tasks) → «مهمة واحدة», 2 → «مهمتان», 5 → «5 مهام», 12 → «12 مهمة».
String count(num n, List<String> forms) {
  if (n == 1) return forms[0];
  if (n == 2) return forms[1];
  if (n >= 3 && n <= 10) return '$n ${forms[2]}';
  return '$n ${forms[3]}';
}

const tasksForms = ['مهمة واحدة', 'مهمتان', 'مهام', 'مهمة'];
const itemsForms = ['بند واحد', 'بندان', 'بنود', 'بنداً'];
const pointsForms = ['نقطة واحدة', 'نقطتان', 'نقاط', 'نقطة'];
const hoursForms = ['ساعة واحدة', 'ساعتان', 'ساعات', 'ساعة'];

const statusLabels = {
  'pending': 'قيد الانتظار',
  'in_progress': 'قيد العمل',
  'submitted': 'بانتظار الاعتماد',
  'approved': 'منجزة',
  'returned': 'مُعادة',
};
const priorityLabels = {'normal': 'عادية', 'high': 'مهمة', 'urgent': 'عاجلة'};
const kindLabels = {'house': 'سكن', 'company': 'شركة', 'personal': 'شخصية'};
const specialtyLabels = {
  'frontend': 'واجهات',
  'backend': 'خادم',
  'design': 'تصميم',
  'qa': 'اختبار',
  'pm': 'إدارة مشاريع',
};
const slotLabels = {'morning': 'صباحاً', 'afternoon': 'ظهراً', 'evening': 'مساءً', 'any': 'أي وقت'};
/// One-letter day initials (Sunday first), as on Arabic calendars.
const dayInitials = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
