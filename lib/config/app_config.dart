import 'package:flutter/foundation.dart';

/// База REST API — как `web/src/config/apiBase.js`.
///
/// По умолчанию (release и `flutter run` на телефоне): `https://api.tojir.tj/api/v1`
///
/// Локальный Django только с `--dart-define=API_HOST=...`:
///   эмулятор Android: `API_HOST=10.0.2.2`
///   физический телефон: `API_HOST=192.168.x.x` (см. `run_dev.ps1`)
class AppConfig {
  AppConfig._();

  static const String _prodApi = 'https://api.tojir.tj/api/v1';
  static const String _prodOffer = 'https://tojir.tj/offer';

  static const String _envApiBase = String.fromEnvironment('API_BASE');
  static const String _envApiHost = String.fromEnvironment('API_HOST');
  static const bool _useProdApi = bool.fromEnvironment('USE_PROD_API');

  static String get apiBase {
    final fromEnv = _normalize(_envApiBase);
    if (fromEnv != null) return fromEnv;
    if (!kDebugMode || _useProdApi) return _prodApi;
    if (_envApiHost.isEmpty) return _prodApi;
    return _normalize('http://$_envApiHost:8001/api/v1')!;
  }

  static String get offerUrl {
    const fromEnv = String.fromEnvironment('OFFER_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (!kDebugMode || _useProdApi) return _prodOffer;
    if (_envApiHost.isEmpty) return _prodOffer;
    final host = _envApiHost == '127.0.0.1' ? '127.0.0.1' : _envApiHost;
    return 'http://$host:8002/offer';
  }

  static String? _normalize(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'/+$'), '');
    return s.isEmpty ? null : s;
  }
}
