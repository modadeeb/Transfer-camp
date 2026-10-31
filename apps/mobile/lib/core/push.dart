import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

enum PushState { on, off, denied, notConfigured, unsupported, error }

/// Firebase Cloud Messaging for Android. Firebase is configured from the server
/// (GET /api/push/config → android), so the app needs no google-services.json.
class Push {
  Push(this.api);

  final Api api;
  void Function(String link)? onOpenLink;
  VoidCallback? onMessage;

  static const _prefKey = 'push_enabled';
  static const _channel = AndroidNotificationChannel('camp', 'إشعارات المعسكر', description: 'المهام والتذكيرات والتنبيهات', importance: Importance.high);

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _listening = false;
  String? _token;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get wanted => api.prefs.getBool(_prefKey) ?? false;

  Future<FirebaseOptions?> _options() async {
    final r = await api.get('/push/config');
    final a = r['android'];
    if (r['enabled'] != true || a is! Map) return null;
    String s(String k) => '${a[k] ?? ''}';
    if (s('apiKey').isEmpty || s('appId').isEmpty || s('messagingSenderId').isEmpty || s('projectId').isEmpty) return null;
    return FirebaseOptions(apiKey: s('apiKey'), appId: s('appId'), messagingSenderId: s('messagingSenderId'), projectId: s('projectId'));
  }

  Future<bool> _init() async {
    if (_ready) return true;
    final options = await _options();
    if (options == null) return false;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
    await _local.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (resp) {
        final link = resp.payload;
        if (link != null && link.startsWith('/')) onOpenLink?.call(link);
      },
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
    _ready = true;
    return true;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _open(m.data);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen(_register);
  }

  void _open(Map<String, dynamic> data) {
    final link = '${data['link'] ?? ''}';
    if (link.startsWith('/')) onOpenLink?.call(link);
  }

  Future<void> _showForeground(RemoteMessage m) async {
    onMessage?.call();
    final title = m.notification?.title ?? '${m.data['title'] ?? ''}';
    final body = m.notification?.body ?? '${m.data['body'] ?? ''}';
    if (title.isEmpty) return;
    await _local.show(
      m.hashCode,
      title,
      body.isEmpty ? null : body,
      NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name, channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
      ),
      payload: '${m.data['link'] ?? '/'}',
    );
  }

  Future<void> _register(String token) async {
    _token = token;
    await api.post('/devices', {'token': token, 'platform': 'android'});
  }

  /// Called after sign-in: re-registers the device if the user enabled push before.
  Future<void> resume() async {
    if (!supported || !wanted) return;
    try {
      if (!await _init()) return;
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) return;
      _listen();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('push resume failed: $e');
    }
  }

  Future<PushState> state() async {
    if (!supported) return PushState.unsupported;
    try {
      if (await _options() == null) return PushState.notConfigured;
    } on ApiException {
      return PushState.error;
    }
    if (!wanted) return PushState.off;
    if (!_ready) return PushState.off;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    if (s.authorizationStatus == AuthorizationStatus.denied) return PushState.denied;
    return s.authorizationStatus == AuthorizationStatus.authorized ? PushState.on : PushState.off;
  }

  Future<PushState> enable() async {
    if (!supported) return PushState.unsupported;
    if (!await _init()) return PushState.notConfigured;
    final s = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    if (s.authorizationStatus == AuthorizationStatus.denied) return PushState.denied;
    _listen();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return PushState.error;
    await _register(token);
    await api.prefs.setBool(_prefKey, true);
    return PushState.on;
  }

  Future<PushState> disable() async {
    await api.prefs.setBool(_prefKey, false);
    try {
      final token = _token ?? (_ready ? await FirebaseMessaging.instance.getToken() : null);
      if (token != null) await api.post('/devices/remove', {'token': token});
      if (_ready) await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('push disable: $e');
    }
    _token = null;
    return PushState.off;
  }

  /// Unregisters this device on sign-out so the next user doesn't get these notifications.
  Future<void> signOut() async {
    final token = _token;
    if (token == null) return;
    try {
      await api.post('/devices/remove', {'token': token});
    } catch (_) {
      // best effort
    }
  }

  static String describe(PushState s) => switch (s) {
        PushState.on => 'مفعّلة على هذا الجهاز',
        PushState.off => 'غير مفعّلة على هذا الجهاز',
        PushState.denied => 'الإشعارات ممنوعة لهذا التطبيق. فعّلها من إعدادات الجوال ← التطبيقات ← معسكر نقلة ← الإشعارات.',
        PushState.notConfigured => 'لم يُضبط Firebase على الخادم بعد. اطلب من المدير إكمال إعداد الإشعارات.',
        PushState.unsupported => 'الإشعارات مدعومة على أندرويد فقط حالياً.',
        PushState.error => 'تعذّر الاتصال بالخادم. حاول مرة أخرى.',
      };
}
