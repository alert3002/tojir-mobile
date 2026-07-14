import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../utils/platform_info.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minVersion,
    required this.message,
    required this.storeUrl,
    required this.force,
    required this.optional,
  });

  final String currentVersion;
  final String latestVersion;
  final String minVersion;
  final String message;
  final String storeUrl;
  final bool force;
  final bool optional;
}

/// Сравнение semver: a < b → отрицательное, a == b → 0, a > b → положительное.
int compareSemver(String a, String b) {
  List<int> parts(String v) {
    final clean = v.trim().split('+').first.split('-').first;
    return clean
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class AppUpdateService {
  AppUpdateService._();

  static const _dismissedKey = 'app_update_dismissed_version';

  /// Возвращает info, если нужно показать диалог; иначе null.
  static Future<AppUpdateInfo?> check() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version.trim();
      if (current.isEmpty) return null;

      final base = AppConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$base/app/version/');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! Map) return null;

      final latest = (data['latest_version'] ?? '').toString().trim();
      final minimum = (data['min_version'] ?? '').toString().trim();
      final message = (data['message'] ?? '').toString().trim();
      final androidUrl = (data['android_url'] ?? '').toString().trim();
      final iosUrl = (data['ios_url'] ?? '').toString().trim();
      final storeUrl = isIosApp ? iosUrl : androidUrl;

      if (latest.isEmpty && minimum.isEmpty) return null;

      final belowMin = minimum.isNotEmpty && compareSemver(current, minimum) < 0;
      final belowLatest = latest.isNotEmpty && compareSemver(current, latest) < 0;

      if (belowMin) {
        return AppUpdateInfo(
          currentVersion: current,
          latestVersion: latest.isNotEmpty ? latest : minimum,
          minVersion: minimum,
          message: message.isNotEmpty
              ? message
              : 'Эта версия устарела. Обновите приложение, чтобы продолжить.',
          storeUrl: storeUrl,
          force: true,
          optional: false,
        );
      }

      if (!belowLatest) return null;

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_dismissedKey) ?? '';
      if (dismissed == latest) return null;

      return AppUpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        minVersion: minimum,
        message: message.isNotEmpty
            ? message
            : 'Доступна новая версия $latest. Рекомендуем обновить приложение.',
        storeUrl: storeUrl,
        force: false,
        optional: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AppUpdateService.check: $e');
      return null;
    }
  }

  static Future<void> dismissOptional(String latestVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, latestVersion);
  }

  static Future<void> openStore(String url) async {
    final raw = url.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
