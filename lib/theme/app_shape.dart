import 'package:flutter/material.dart';

/// Сучасна геометрія M3 (2024–2027): м’які радіуси, єдиний стиль по всьому застосунку.
abstract final class AppShape {
  /// Кнопки, поля, дрібні картки
  static const double radius = 14;

  /// Великі картки, модальні панелі
  static const double radiusLg = 20;

  static BorderRadius get br => BorderRadius.circular(radius);

  static BorderRadius get brLg => BorderRadius.circular(radiusLg);

  static BorderRadius get sheetTop => const BorderRadius.vertical(top: Radius.circular(radiusLg));

  static RoundedRectangleBorder get roundedRect => RoundedRectangleBorder(borderRadius: br);

  static RoundedRectangleBorder get roundedRectLg => RoundedRectangleBorder(borderRadius: brLg);

  static BoxDecoration sheetHandle(Color color) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      );
}
