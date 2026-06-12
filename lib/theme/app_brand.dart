import 'package:flutter/material.dart';

/// Единая палитра и отступы Tojir — зеркало web `--tojir-*` / Ant Design tokens.
abstract final class AppBrand {
  static const Color seed = Color(0xFF4F46E5);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryHover = Color(0xFF1D4ED8);

  static const Color lightPage = Color(0xFFF1F5F9);
  static const Color darkPage = Color(0xFF0C111C);
  static const Color darkCard = Color(0xFF151D2E);
  static const Color darkRow = Color(0xFF1A2438);
  static const Color darkSheet = Color(0xFF151D2E);

  static const Color textMutedDark = Color(0xFF94A3B8);
  static const Color navActiveDark = Color(0xFF93C5FD);
  static const Color debtWeAccent = Color(0xFFE11D48);
  static const Color debtClientAccent = Color(0xFF059669);

  static const double bottomNavHeight = 64;
  static const double shellContentBottomPad = 72;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(12, 8, 12, shellContentBottomPad);
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(10, 10, 10, 12);
  static const double titleSize = 20;
  static const double gapAfterTitle = 8;
  static const double gapSection = 10;
  static const double gapInCard = 8;

  static TextStyle pageTitle(ColorScheme cs) => TextStyle(
        fontSize: titleSize,
        fontWeight: FontWeight.w900,
        color: cs.onSurface,
        height: 1.2,
      );

  static BoxDecoration cardDecoration(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: cs.surfaceContainerLow,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: dark ? 0.28 : 0.45),
      ),
    );
  }

  static BoxDecoration rowDecoration(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: cs.surfaceContainer,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: dark ? 0.2 : 0.35),
      ),
    );
  }
}
