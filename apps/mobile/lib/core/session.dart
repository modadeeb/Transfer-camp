import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api.dart';

enum SessionStatus { loading, signedOut, signedIn, offline }

/// Who is signed in. Mirrors apps/web/src/stores/session.js.
class Session extends ChangeNotifier {
  Session(this.api) {
    api.onUnauthorized = _expired;
  }

  final Api api;
  SessionStatus status = SessionStatus.loading;
  User? user;
  String campName = 'معسكر نقلة';
  String? error;
  List<User> members = [];

  bool get isManager => user?.isManager ?? false;
  bool get mustChangePassword => user?.mustChangePassword ?? false;

  String memberName(int? id) {
    if (id == null) return 'غير مُسنَدة';
    for (final m in members) {
      if (m.id == id) return m.name;
    }
    return id == user?.id ? (user?.name ?? '') : '—';
  }

  Future<void> restore() async {
    status = SessionStatus.loading;
    error = null;
    notifyListeners();
    try {
      final r = await api.get('/auth/me');
      _apply(r);
      status = SessionStatus.signedIn;
      await loadMembers();
    } on ApiException catch (e) {
      if (e.unauthorized) {
        status = SessionStatus.signedOut;
      } else {
        error = e.message;
        status = SessionStatus.offline;
      }
    }
    notifyListeners();
  }

  void _apply(Map<String, dynamic> r) {
    if (r['user'] is Map<String, dynamic>) user = User(r['user'] as Map<String, dynamic>);
    if (r['campName'] is String) campName = r['campName'] as String;
  }

  Future<void> loadMembers() async {
    try {
      final r = await api.get('/members');
      members = listOf(r['members'], User.new);
      notifyListeners();
    } on ApiException {
      // members list is optional for rendering names; keep the previous one
    }
  }

  Future<void> login(String username, String password) async {
    final r = await api.post('/auth/login', {'username': username.trim(), 'password': password, 'remember': true});
    _apply(r);
    final me = await api.get('/auth/me');
    _apply(me);
    status = SessionStatus.signedIn;
    error = null;
    notifyListeners();
    await loadMembers();
  }

  Future<void> changePassword(String current, String next) async {
    await api.post('/auth/password', {'current': current, 'password': next});
    final me = await api.get('/auth/me');
    _apply(me);
    notifyListeners();
  }

  void setUser(Map<String, dynamic> raw) {
    user = User(raw);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // signing out locally is enough when the server is unreachable
    }
    await api.clearSession();
    user = null;
    members = [];
    status = SessionStatus.signedOut;
    notifyListeners();
  }

  void _expired() {
    if (status != SessionStatus.signedIn) return;
    api.clearSession();
    user = null;
    status = SessionStatus.signedOut;
    error = 'انتهت الجلسة. سجّل الدخول مرة أخرى';
    notifyListeners();
  }
}
