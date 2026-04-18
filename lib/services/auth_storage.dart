import 'package:shared_preferences/shared_preferences.dart';

/// Ключи как во веб: tojir_token, tojir_refresh, tojir_user
class AuthStorage {
  static const _kAccess = 'tojir_token';
  static const _kRefresh = 'tojir_refresh';
  static const _kUser = 'tojir_user';

  Future<String?> get accessToken async =>
      (await SharedPreferences.getInstance()).getString(_kAccess);

  Future<String?> get refreshToken async =>
      (await SharedPreferences.getInstance()).getString(_kRefresh);

  Future<String?> get userJson async =>
      (await SharedPreferences.getInstance()).getString(_kUser);

  Future<void> setTokens({required String access, String? refresh}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccess, access);
    if (refresh != null) {
      await p.setString(_kRefresh, refresh);
    }
  }

  Future<void> setUserJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUser, json);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
    await p.remove(_kUser);
  }
}
