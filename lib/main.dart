import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // iOS can crash at startup if FCM is wired but Firebase isn't configured with real keys/plist.
    // Keep the app usable without push until Firebase is configured.
    if (!DefaultFirebaseOptions.isPlaceholderConfig) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await PushService.instance.ensureFirebaseInitialized();
    } else {
      debugPrint('Firebase disabled: placeholder config detected (replace firebase_options.dart + GoogleService-Info.plist).');
    }
  }
  runApp(const ProviderScope(child: TojirApp()));
}
