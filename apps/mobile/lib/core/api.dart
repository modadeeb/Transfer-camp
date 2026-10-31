import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default server; can be overridden at build time (--dart-define=API_BASE=https://…)
/// or from the login screen (stored on the device).
const String kDefaultServer = String.fromEnvironment('API_BASE', defaultValue: 'https://transfer-camp.moadeebprog.workers.dev');

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.fields = const {}});
  final String message;
  final int status;
  final Map<String, String> fields;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// HTTP client for the Worker API. The session lives in the same httpOnly cookie the web app uses,
/// kept in a persistent cookie jar so the user stays signed in between launches.
class Api {
  Api._(this._dio, this._jar, this._prefs, this.server);

  final Dio _dio;
  final PersistCookieJar _jar;
  final SharedPreferences _prefs;
  String server;

  /// Called when any request comes back 401 (session ended elsewhere).
  void Function()? onUnauthorized;

  static const _serverKey = 'server_url';

  static Future<Api> create() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(storage: FileStorage('${dir.path}/cookies'), ignoreExpires: false);
    final server = normalizeServer(prefs.getString(_serverKey) ?? kDefaultServer);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
      headers: {'X-Requested-With': 'camp', 'Accept': 'application/json'},
    ));
    dio.interceptors.add(CookieManager(jar));
    return Api._(dio, jar, prefs, server);
  }

  static String normalizeServer(String url) {
    var s = url.trim();
    if (s.isEmpty) return kDefaultServer;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> setServer(String url) async {
    server = normalizeServer(url);
    await _prefs.setString(_serverKey, server);
  }

  SharedPreferences get prefs => _prefs;

  Future<void> clearSession() => _jar.deleteAll();

  Future<Map<String, dynamic>> get(String path, [Map<String, dynamic>? query]) => _send('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<Map<String, dynamic>> patch(String path, [Object? body]) => _send('PATCH', path, body: body ?? const {});
  Future<Map<String, dynamic>> put(String path, [Object? body]) => _send('PUT', path, body: body ?? const {});
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    final q = <String, dynamic>{};
    query?.forEach((k, v) {
      if (v != null && v != '') q[k] = v is bool ? (v ? '1' : '0') : '$v';
    });
    Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        '$server/api$path',
        data: body,
        queryParameters: q.isEmpty ? null : q,
        options: Options(method: method, contentType: body == null ? null : Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw ApiException(_networkMessage(e));
    }
    final data = res.data;
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return map;
    if (status == 401 && !path.startsWith('/auth/login')) onUnauthorized?.call();
    final fields = <String, String>{};
    if (map['fields'] is Map) {
      (map['fields'] as Map).forEach((k, v) => fields['$k'] = '$v');
    }
    final message = map['error'] is String ? map['error'] as String : _statusMessage(status, data);
    throw ApiException(message, status: status, fields: fields);
  }

  String _statusMessage(int status, Object? data) {
    if (status == 404) return 'العنصر غير موجود';
    if (status >= 500) return 'الخادم لا يستجيب حالياً. حاول بعد قليل';
    if (data is String && data.contains('<html')) return 'الرد ليس من خادم المعسكر. تأكد من عنوان الخادم';
    return 'تعذّر إتمام الطلب ($status)';
  }

  String _networkMessage(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
      return 'انتهت مهلة الاتصال. تحقق من الإنترنت';
    }
    if (e.error is SocketException || e.type == DioExceptionType.connectionError) {
      return 'لا يوجد اتصال بالخادم. تحقق من الإنترنت أو من عنوان الخادم';
    }
    if (e.error is HandshakeException) return 'تعذّر الاتصال الآمن بالخادم';
    return 'تعذّر الاتصال بالخادم';
  }
}
