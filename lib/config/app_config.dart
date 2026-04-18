/// База REST API — как `web/src/config/apiBase.js`.
///
/// Сборка под свой сервер:
/// `flutter run --dart-define=API_BASE=https://api.tojir.tj/api/v1`
class AppConfig {
  AppConfig._();

  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://api.tojir.tj/api/v1',
  );

  /// Полная версия оферты (как во вебе `/offer`).
  static const String offerUrl = String.fromEnvironment(
    'OFFER_URL',
    defaultValue: 'https://tojir.tj/offer',
  );
}
