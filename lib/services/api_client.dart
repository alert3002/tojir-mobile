import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_storage.dart';

/// HTTP-клиент переписан на Dio для Interceptors, но для обратной совместимости возвращает http.Response.
/// Постепенно (incremental) вы можете менять экраны, чтобы использовать Dio напрямую.
class ApiClient {
  late final Dio _dio;
  final AuthStorage _storage;

  String _cleanUrl(String path) {
    final b = AppConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$b/$p';
  }

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      // We don't use baseUrl here to ensure absolute path string concatenation isn't mangled by Dio
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status < 500, // Handle errors gracefully
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final t = await _storage.accessToken;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          options.headers['Content-Type'] = 'application/json';
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            final refresh = await _storage.refreshToken;
            if (refresh != null && refresh.isNotEmpty) {
              try {
                final refreshOptions = Options(headers: {'Content-Type': 'application/json'});
                final b = AppConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
                final res = await Dio().post(
                  '$b/auth/jwt/token/refresh/',
                  options: refreshOptions,
                  data: jsonEncode({'refresh': refresh}),
                );
                
                if (res.statusCode == 200) {
                  final data = res.data is String ? jsonDecode(res.data) : res.data;
                  final access = data['access'] as String;
                  final nextRefresh = data['refresh'] as String?;
                  await _storage.setTokens(access: access, refresh: nextRefresh);
                  
                  e.requestOptions.headers['Authorization'] = 'Bearer $access';
                  final retryRes = await Dio().fetch(e.requestOptions);
                  return handler.resolve(retryRes);
                }
              } catch (_) {
                // If refresh fails, just let 401 pass
              }
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  http.Response _toHttpResponse(Response<dynamic> res) {
    var bodyStr = res.data?.toString() ?? '';
    final headers = <String, String>{};
    res.headers.map.forEach((k, v) => headers[k] = v.join(','));
    return http.Response(bodyStr, res.statusCode ?? 500, headers: headers);
  }

  Future<http.Response> get(String path, {bool withAuth = true}) async {
    final res = await _dio.get(_cleanUrl(path));
    return _toHttpResponse(res);
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    final res = await _dio.post(_cleanUrl(path), data: body == null ? null : jsonEncode(body));
    return _toHttpResponse(res);
  }

  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    final res = await _dio.patch(_cleanUrl(path), data: body == null ? null : jsonEncode(body));
    return _toHttpResponse(res);
  }

  Future<http.Response> delete(String path, {bool withAuth = true}) async {
    final res = await _dio.delete(_cleanUrl(path));
    return _toHttpResponse(res);
  }
}
