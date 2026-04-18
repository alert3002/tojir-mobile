import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_keys.dart';
import '../firebase_options.dart';
import 'api_client.dart';

const kPushPrefKey = 'tojir_push_notifications_enabled';

String _pushPlatformLabel() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'android',
  };
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (DefaultFirebaseOptions.isPlaceholderConfig) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushService {
  PushService._();
  static final instance = PushService._();

  String? _cachedToken;
  bool _listenersAttached = false;

  Future<bool> ensureFirebaseInitialized() async {
    if (kIsWeb) return false;
    if (DefaultFirebaseOptions.isPlaceholderConfig) return false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      return true;
    } catch (e) {
      debugPrint('Firebase init: $e');
      return false;
    }
  }

  Future<bool> pushPrefOn() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPushPrefKey) != '0';
  }

  void _attachListenersOnce(ApiClient api) {
    if (_listenersAttached) return;
    _listenersAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      unawaited(_registerToken(api, t));
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      final title = n?.title ?? message.data['title'] ?? 'Tojir';
      final body = n?.body ?? message.data['body'] ?? '';
      final text = body.isEmpty ? title : '$title: $body';
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 5)),
      );
    });
  }

  Future<void> _registerToken(ApiClient api, String token) async {
    if (!await pushPrefOn()) return;
    try {
      final platform = _pushPlatformLabel();
      final res = await api.post('me/push-token/', body: {'token': token, 'platform': platform});
      if (res.statusCode == 200 || res.statusCode == 201) {
        _cachedToken = token;
      }
    } catch (_) {}
  }

  /// После входа: если push включён в настройках — отправить текущий токен на сервер.
  Future<void> syncAfterLogin(ApiClient api) async {
    if (kIsWeb) return;
    if (!await pushPrefOn()) return;
    if (!await ensureFirebaseInitialized()) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) {
        await _registerToken(api, t);
      }
      _attachListenersOnce(api);
    } catch (_) {}
  }

  /// Включение в UI: разрешение ОС + регистрация токена.
  Future<void> requestNotificationPermissionAndRegister(BuildContext context, ApiClient api) async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Push в браузере не поддерживается — используйте приложение Android/iOS.')),
        );
      }
      return;
    }
    if (!await ensureFirebaseInitialized()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Firebase не настроен: в консоли Firebase создайте проект, скачайте google-services.json и GoogleService-Info.plist, выполните flutterfire configure.',
            ),
          ),
        );
      }
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final st = await Permission.notification.request();
      if (!st.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Разрешение на уведомления не выдано')),
          );
        }
        return;
      }
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final apns = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (apns.authorizationStatus != AuthorizationStatus.authorized &&
          apns.authorizationStatus != AuthorizationStatus.provisional) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Уведомления отключены в настройках iOS')),
          );
        }
        return;
      }
    }
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) {
        await _registerToken(api, t);
      }
      _attachListenersOnce(api);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Push подключён: токен отправлен на сервер')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось получить токен FCM: $e')),
        );
      }
    }
  }

  Future<void> unregisterFromServer(ApiClient api) async {
    if (kIsWeb) return;
    var t = _cachedToken;
    if (DefaultFirebaseOptions.isPlaceholderConfig) {
      // Without Firebase we can't fetch a token; still try server cleanup if we cached one earlier.
      if (t == null || t.isEmpty) return;
    } else if (!await ensureFirebaseInitialized()) {
      return;
    }
    if (t == null || t.isEmpty) {
      try {
        t = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    if (t != null && t.isNotEmpty) {
      try {
        await api.delete('me/push-token/?token=${Uri.encodeQueryComponent(t)}');
      } catch (_) {}
    }
    _cachedToken = null;
    if (!DefaultFirebaseOptions.isPlaceholderConfig) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }
}
