import 'package:flutter/material.dart';

/// Радиусы как web: --tojir-radius-sm/md/lg (10 / 14 / 18).
abstract final class AppShape {
  static const double radiusSm = 10;
  static const double radius = 14;
  static const double radiusLg = 18;

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
