import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/platform_info.dart';
import 'auth_storage.dart';
import 'dio_http_setup.dart';

/// HTTP-клиент на Dio. При 401 автоматически обновляет access token через refresh.
class ApiClient {
  late final Dio _dio;
  final AuthStorage _storage;
  Future<String?>? _refreshInFlight;

  String _ensureDjangoTrailingSlash(String path) {
    // Django APPEND_SLASH: без / перед ? — 301; в браузере при редиректе теряется Authorization → 401.
    final qIdx = path.indexOf('?');
    final hashIdx = path.indexOf('#');
    var splitIdx = path.length;
    if (qIdx >= 0) splitIdx = qIdx;
    if (hashIdx >= 0 && hashIdx < splitIdx) splitIdx = hashIdx;
    final pathPart = path.substring(0, splitIdx);
    final suffix = path.substring(splitIdx);
    if (pathPart.isEmpty || pathPart.endsWith('/')) return path;
    return '$pathPart/$suffix';
  }

  String _cleanUrl(String path) {
    final b = AppConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$b/${_ensureDjangoTrailingSlash(p)}';
  }

  bool _isAuthPath(String path) {
    final p = path.toLowerCase();
    return p.contains('auth/request-sms') ||
        p.contains('auth/verify-sms') ||
        p.contains('auth/jwt/token/refresh') ||
        p.contains('auth/jwt/token/');
  }

  bool _isTransientNetworkError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    return isSocketLikeError(e.error);
  }

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      // 4xx/5xx как обычный ответ — иначе Dio кидает DioException и App Review видит стек.
      validateStatus: (status) => status != null && status < 600,
    ));

    if (!kIsWeb) {
      configureDioHttpClient(_dio);
    }

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final t = await _storage.accessToken;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          options.headers['Content-Type'] = 'application/json';
          options.headers['Connection'] = 'close';
          if (isIosApp) {
            options.headers['X-Tojir-Client'] = 'ios';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          final retried = await _retryIfUnauthorized(response.requestOptions, response.statusCode);
          if (retried != null) {
            return handler.resolve(retried);
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          if (_isTransientNetworkError(e) && e.requestOptions.extra['conn_retry'] != true) {
            final opts = e.requestOptions.copyWith(
              extra: Map<String, dynamic>.from(e.requestOptions.extra)
                ..['conn_retry'] = true,
            );
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (retryErr) {
              if (retryErr is DioException) {
                e = retryErr;
              } else {
                return handler.next(e);
              }
            }
          }

          final status = e.response?.statusCode;
          final retried = await _retryIfUnauthorized(e.requestOptions, status);
          if (retried != null) {
            return handler.resolve(retried);
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<Response<dynamic>?> _retryIfUnauthorized(
    RequestOptions requestOptions,
    int? statusCode,
  ) async {
    if (statusCode != 401) return null;
    if (_isAuthPath(requestOptions.uri.path)) return null;
    if (requestOptions.extra['retried_after_refresh'] == true) return null;

    final access = await _refreshAccessToken();
    if (access == null || access.isEmpty) return null;

    final opts = requestOptions.copyWith(
      headers: Map<String, dynamic>.from(requestOptions.headers)
        ..['Authorization'] = 'Bearer $access',
      extra: Map<String, dynamic>.from(requestOptions.extra)
        ..['retried_after_refresh'] = true,
    );
    try {
      return await _dio.fetch(opts);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _refreshAccessToken() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }
    _refreshInFlight = _doRefreshAccessToken();
    try {
      return await _refreshInFlight!;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<String?> _doRefreshAccessToken() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final b = AppConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status != null && status < 500,
        ),
      ).post(
        '$b/auth/jwt/token/refresh/',
        options: Options(headers: {'Content-Type': 'application/json', 'Connection': 'close'}),
        data: jsonEncode({'refresh': refresh}),
      );
      if (res.statusCode != 200) return null;

      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is! Map) return null;
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) return null;

      final nextRefresh = data['refresh'] as String?;
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        await _storage.setTokens(access: access, refresh: nextRefresh);
      } else {
        await _storage.setTokens(access: access, refresh: refresh);
      }
      return access;
    } catch (_) {
      return null;
    }
  }

  http.Response _toHttpResponse(Response<dynamic> res) {
    final bodyStr = res.data?.toString() ?? '';
    final headers = <String, String>{};
    res.headers.map.forEach((k, v) => headers[k] = v.join(','));
    return http.Response(bodyStr, res.statusCode ?? 500, headers: headers);
  }

  Future<http.Response> get(String path, {bool withAuth = true}) async {
    try {
      final res = await _dio.get(_cleanUrl(path));
      return _toHttpResponse(res);
    } on DioException catch (e) {
      return _dioErrorToResponse(e);
    }
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    try {
      final res = await _dio.post(_cleanUrl(path), data: body == null ? null : jsonEncode(body));
      return _toHttpResponse(res);
    } on DioException catch (e) {
      return _dioErrorToResponse(e);
    }
  }

  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    try {
      final res = await _dio.patch(_cleanUrl(path), data: body == null ? null : jsonEncode(body));
      return _toHttpResponse(res);
    } on DioException catch (e) {
      return _dioErrorToResponse(e);
    }
  }

  Future<http.Response> delete(String path, {bool withAuth = true}) async {
    try {
      final res = await _dio.delete(_cleanUrl(path));
      return _toHttpResponse(res);
    } on DioException catch (e) {
      return _dioErrorToResponse(e);
    }
  }

  http.Response _dioErrorToResponse(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) {
      return http.Response(e.response?.data?.toString() ?? '', status);
    }
    // Сеть / таймаут — без стека DioException для пользователя.
    throw Exception('Нет связи с сервером. Проверьте интернет и попробуйте снова.');
  }

  /// Обновить access token (при старте и после возврата из фона).
  Future<bool> refreshSession() async {
    final access = await _refreshAccessToken();
    return access != null && access.isNotEmpty;
  }
}
