// Сгенерируйте реальные значения: `dart pub global activate flutterfire_cli` затем `flutterfire configure`
// Пока указаны плейсхолдеры — замените на данные из Firebase Console (один проект, приложения Android + iOS).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('FCM для веб не настроен');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('FCM только для Android и iOS');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    appId: '1:987654321098:android:a1b2c3d4e5f678901234',
    messagingSenderId: '987654321098',
    projectId: 'tojir-app-placeholder',
    storageBucket: 'tojir-app-placeholder.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    appId: '1:987654321098:ios:a1b2c3d4e5f678901235',
    messagingSenderId: '987654321098',
    projectId: 'tojir-app-placeholder',
    storageBucket: 'tojir-app-placeholder.appspot.com',
    iosBundleId: 'tj.tojir.tojirApp',
  );
}
