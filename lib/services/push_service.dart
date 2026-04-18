import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

const kPushPrefKey = 'tojir_push_notifications_enabled';

class PushService {
  PushService._();
  static final instance = PushService._();

  String? _cachedToken;

  Future<bool> pushPrefOn() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPushPrefKey) != '0';
  }

  /// Mobile push (FCM/APNs) is not shipped in this build.
  Future<bool> ensureFirebaseInitialized() async => false;

  /// After login: no-op (no device token without Firebase).
  Future<void> syncAfterLogin(ApiClient api) async {
    // Keep method for call-sites; server-side notifications history still works.
    return;
  }

  Future<void> requestNotificationPermissionAndRegister(BuildContext context, ApiClient api) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Push-уведомления в этом билде отключены (Firebase удалён). История уведомлений на сервере доступна ниже.',
          ),
        ),
      );
    }
  }

  Future<void> unregisterFromServer(ApiClient api) async {
    var t = _cachedToken;
    if (t == null || t.isEmpty) {
      // Best-effort: nothing to unregister without a cached token.
      return;
    }
    try {
      await api.delete('me/push-token/?token=${Uri.encodeQueryComponent(t)}');
    } catch (_) {}
    _cachedToken = null;
  }
}
