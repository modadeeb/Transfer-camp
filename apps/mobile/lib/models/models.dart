import 'dart:ui';

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
num _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) ?? 0 : 0);
String? _str(Object? v) => v?.toString();
bool _bool(Object? v) => v == true || v == 1 || v == '1';

Color parseColor(String? hex, Color fallback) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return fallback;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

class User {
  User(this.raw);
  final Map<String, dynamic> raw;

  int get id => _int(raw['id'])!;
  String get username => _str(raw['username']) ?? '';
  String get name => _str(raw['name']) ?? '';
  String get role => _str(raw['role']) ?? 'member';
  bool get isManager => role == 'manager';
  String? get specialty => _str(raw['specialty']);
  String? get phone => _str(raw['phone']);
  String? get color => _str(raw['color']);
  bool get mustChangePassword => _bool(raw['mustChangePassword']);
  bool get archived => raw['archivedAt'] != null;
  Map<String, dynamic> get settings => raw['settings'] is Map<String, dynamic> ? raw['settings'] as Map<String, dynamic> : const {};
}

class ChecklistItem {
  ChecklistItem(this.id, this.text, this.done);
  final String id;
  final String text;
  final bool done;
}

class Attachment {
  Attachment(this.url, this.label);
  final String url;
  final String? label;
}

class Task {
  Task(this.raw);
  final Map<String, dynamic> raw;

  int get id => _int(raw['id'])!;
  String get kind => _str(raw['kind']) ?? 'house';
  String get title => _str(raw['title']) ?? '';
  String? get details => _str(raw['details']);
  int? get assigneeId => _int(raw['assigneeId']);
  String? get assigneeName => _str(raw['assigneeName']);
  String? get assigneeColor => _str(raw['assigneeColor']);
  String? get projectName => _str(raw['projectName']);
  String? get specialty => _str(raw['specialty']);
  String? get dueDate => _str(raw['dueDate']);
  String? get dueTime => _str(raw['dueTime']);
  String get priority => _str(raw['priority']) ?? 'normal';
  num get size => _num(raw['size']);
  String get recurrence => _str(raw['recurrence']) ?? 'none';
  bool get needsApproval => _bool(raw['needsApproval']);
  String get status => _str(raw['status']) ?? 'pending';
  String? get completionNote => _str(raw['completionNote']);
  String? get completionUrl => _str(raw['completionUrl']);
  String? get returnNote => _str(raw['returnNote']);
  bool get archived => raw['archivedAt'] != null;
  bool get isDone => status == 'approved';
  bool get isOpen => status == 'pending' || status == 'in_progress' || status == 'returned';

  List<ChecklistItem> get checklist => (raw['checklist'] is List ? raw['checklist'] as List : const [])
      .whereType<Map>()
      .map((m) => ChecklistItem('${m['id'] ?? ''}', '${m['text'] ?? ''}', _bool(m['done'])))
      .toList();

  List<Attachment> get attachments => (raw['attachments'] is List ? raw['attachments'] as List : const [])
      .whereType<Map>()
      .map((m) => Attachment('${m['url'] ?? ''}', _str(m['label'])))
      .toList();

  bool isOverdue(String today, String nowTime) {
    final d = dueDate;
    if (d == null || isDone) return false;
    if (d.compareTo(today) < 0) return true;
    final t = dueTime;
    return d == today && t != null && t.compareTo(nowTime) < 0;
  }
}

class AppNotification {
  AppNotification(this.raw);
  final Map<String, dynamic> raw;

  int get id => _int(raw['id'])!;
  String get type => _str(raw['type']) ?? '';
  String get title => _str(raw['title']) ?? '';
  String? get body => _str(raw['body']);
  String? get link => _str(raw['link']);
  bool get urgent => _bool(raw['urgent']);
  bool get read => raw['readAt'] != null;
  String get createdAt => _str(raw['createdAt']) ?? '';
}

List<T> listOf<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    (v is List ? v : const []).whereType<Map<String, dynamic>>().map(f).toList();
