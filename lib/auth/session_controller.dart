import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/push_service.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._storage, this._api);

  final AuthStorage _storage;
  final ApiClient _api;

  static const _keepAliveInterval = Duration(hours: 3);

  Map<String, dynamic>? _user;
  bool _ready = false;
  String? _bootstrapError;
  Timer? _keepAliveTimer;

  Map<String, dynamic>? get user => _user;
  bool get isReady => _ready;
  bool get isLoggedIn => _user != null;
  String? get bootstrapError => _bootstrapError;

  String? get displayName {
    final u = _user;
    if (u == null) return null;
    final fn = (u['first_name'] as String?)?.trim() ?? '';
    final ln = (u['last_name'] as String?)?.trim() ?? '';
    final full = '$fn $ln'.trim();
    if (full.isNotEmpty) return full;
    return u['phone'] as String?;
  }

  String? get role => _user?['role'] as String?;

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      if (_user == null) return;
      unawaited(_api.refreshSession());
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  @override
  void dispose() {
    _stopKeepAlive();
    super.dispose();
  }

  /// Загрузка профиля при старте (если есть access token).
  Future<void> bootstrap() async {
    _ready = false;
    _bootstrapError = null;
    notifyListeners();

    final token = await _storage.accessToken;
    if (token == null || token.isEmpty) {
      _user = null;
      _ready = true;
      notifyListeners();
      return;
    }

    final cached = await _storage.userJson;
    if (cached != null && cached.isNotEmpty) {
      try {
        _user = jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {
        _user = null;
      }
    }

    await _api.refreshSession();

    try {
      final ok = await _reloadProfileFromServer(clearOnUnauthorized: true);
      if (!ok && _user == null) {
        _bootstrapError = null;
      } else if (!ok && _user != null) {
        _bootstrapError = 'Нет связи с сервером. Проверьте интернет.';
      }
    } catch (e) {
      if (_user == null) {
        _bootstrapError = e.toString();
      }
    }

    _ready = true;
    notifyListeners();
    if (_user != null) {
      _startKeepAlive();
      unawaited(PushService.instance.syncAfterLogin(_api));
    } else {
      _stopKeepAlive();
    }
  }

  /// Обновить профиль без экрана загрузки (не сбрасывает isReady).
  Future<void> reloadUser() async {
    if (_user == null) return;
    await _api.refreshSession();
    try {
      await _reloadProfileFromServer(clearOnUnauthorized: false);
    } catch (_) {}
    notifyListeners();
  }

  /// После возврата из фона: обновить JWT (мӯҳлат +14 рӯз) бе logout.
  Future<void> resumeFromBackground() async {
    if (_user == null) return;
    await _api.refreshSession();
    try {
      await _reloadProfileFromServer(clearOnUnauthorized: false);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> _reloadProfileFromServer({required bool clearOnUnauthorized}) async {
    var res = await _api.get('me/');
    if (res.statusCode == 401) {
      final refreshed = await _api.refreshSession();
      if (refreshed) {
        res = await _api.get('me/');
      }
    }
    if (res.statusCode == 200) {
      _user = jsonDecode(res.body) as Map<String, dynamic>;
      await _storage.setUserJson(res.body);
      _bootstrapError = null;
      return true;
    }
    if (res.statusCode == 401 && clearOnUnauthorized) {
      _stopKeepAlive();
      await _storage.clear();
      _user = null;
      _bootstrapError = null;
      return false;
    }
    if (res.statusCode == 401) {
      return false;
    }
    _bootstrapError = 'Профиль: ${res.statusCode}';
    return false;
  }

  Future<({bool isNewUser, String? debugCode})> requestSmsCode(
    String digits9, {
    String registerAs = 'client',
  }) async {
    final phone = digits9.replaceAll(RegExp(r'\D'), '').trim();
    if (phone.length != 9) {
      throw ArgumentError('Введите 9 цифр после +992');
    }
    try {
      final res = await _api.post(
        'auth/request-sms/',
        body: {'phone': phone, 'register_as': registerAs},
        withAuth: false,
      );
      if (res.statusCode >= 500) {
        throw Exception('Сервер временно недоступен. Попробуйте позже.');
      }
      if (res.statusCode != 200) {
        throw Exception(_parseError(res.body, fallback: 'Не удалось отправить код'));
      }
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) {
        return (isNewUser: false, debugCode: null);
      }
      final debug = data['debug_code'];
      return (
        isNewUser: data['is_new_user'] == true,
        debugCode: kDebugMode && debug != null ? debug.toString() : null,
      );
    } on http.ClientException catch (e) {
      throw Exception('Нет связи с сервером. Проверьте интернет.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Не удалось отправить код. Попробуйте позже.');
    }
  }

  Future<void> loginWithSms({required String digits9, required String code, String ref = ''}) async {
    final phone = digits9.replaceAll(RegExp(r'\D'), '').trim();
    final c = code.replaceAll(RegExp(r'\D'), '').trim();
    if (phone.length != 9) throw ArgumentError('Введите 9 цифр после +992');
    if (c.length != 6) throw ArgumentError('Введите 6-значный код из SMS');

    late final http.Response res;
    try {
      res = await _api.post(
        'auth/verify-sms/',
        body: {'phone': phone, 'code': c, 'ref': ref.trim()},
        withAuth: false,
      );
    } on http.ClientException {
      throw Exception('Нет связи с сервером. Проверьте интернет.');
    }
    if (res.statusCode >= 500) {
      throw Exception('Сервер временно недоступен. Попробуйте позже.');
    }
    if (res.statusCode != 200) {
      throw Exception(_parseError(res.body, fallback: 'Неверный код'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    final u = data['user'];
    if (access == null || u is! Map<String, dynamic>) {
      throw Exception('Неверный ответ сервера');
    }
    await _storage.setTokens(access: access, refresh: refresh);
    _user = u;
    await _storage.setUserJson(jsonEncode(u));
    _startKeepAlive();
    notifyListeners();
    unawaited(PushService.instance.syncAfterLogin(_api));
  }

  Future<void> loginWithPassword(String phone, String password) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      throw ArgumentError('Введите номер телефона');
    }
    final res = await _api.post(
      'auth/jwt/token/',
      // USERNAME_FIELD on the API User model is `phone` (not `username`).
      body: {'phone': digits, 'password': password},
      withAuth: false,
    );
    if (res.statusCode != 200) {
      final err = _parseError(res.body);
      throw Exception(err);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if (access == null) throw Exception('Нет токена в ответе');
    await _storage.setTokens(access: access, refresh: refresh);

    final me = await _api.get('me/');
    if (me.statusCode != 200) {
      await _storage.clear();
      throw Exception('Не удалось загрузить профиль');
    }
    _user = jsonDecode(me.body) as Map<String, dynamic>;
    await _storage.setUserJson(me.body);
    _startKeepAlive();
    notifyListeners();
    unawaited(PushService.instance.syncAfterLogin(_api));
  }

  Future<void> becomeBusinessman() async {
    final res = await _api.post('me/become-businessman/');
    if (res.statusCode != 200) {
      throw Exception(_parseError(res.body, fallback: 'Не удалось сменить роль'));
    }
    final u = jsonDecode(res.body);
    if (u is! Map<String, dynamic>) {
      throw Exception('Неверный ответ сервера');
    }
    _user = u;
    await _storage.setUserJson(jsonEncode(u));
    notifyListeners();
  }

  Future<void> logout() async {
    _stopKeepAlive();
    await PushService.instance.unregisterFromServer(_api);
    await _storage.clear();
    _user = null;
    notifyListeners();
  }

  static String _parseError(String body, {String fallback = 'Ошибка'}) {
    final raw = body.trim();
    if (raw.isEmpty || raw.startsWith('<!DOCTYPE') || raw.startsWith('<html')) {
      return fallback;
    }
    if (raw.contains('DioException') || raw.contains('Exception:')) {
      return fallback;
    }
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        final d = m['detail'];
        if (d is String && d.trim().isNotEmpty) return d.trim();
        final nfe = m['non_field_errors'];
        if (nfe is List && nfe.isNotEmpty) return nfe.first.toString();
        final p = m['phone'];
        if (p is List && p.isNotEmpty) return p.first.toString();
        final c = m['code'];
        if (c is List && c.isNotEmpty) return c.first.toString();
      }
    } catch (_) {}
    if (raw.length > 180) return fallback;
    return fallback;
  }
}
