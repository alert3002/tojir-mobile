import 'package:flutter/material.dart';

/// Токены страницы входа — зеркало web `.tojir-auth-*` + Ant Design dark.
abstract final class AuthTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color offerLink = Color(0xFF60A5FA);
  static const Color requiredRed = Color(0xFFFF4D4F);
  static const Color successGreen = Color(0xFF52C41A);

  static const Color pageBgDark = Color(0xFF0C111C);
  static const Color cardBgDark = Color(0xFF151D2E);
  static const Color inputBgDark = Color(0xFF151D2E);
  static const Color disabledBtnDark = Color(0xFF2D333F);
  static const Color textDark = Color(0xFFF1F5F9);
  static const Color textMutedDark = Color(0xFF94A3B8);
  static const Color borderDark = Color(0x1FFFFFFF);

  static const Color pageBgLight = Color(0xFFF1F5F9);
  static const Color cardBgLight = Color(0xFFF8FAFC);
  static const Color inputBgLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF0F172A);
  static const Color textMutedLight = Color(0xFF64748B);
  static const Color borderLight = Color(0x140F172A);

  static Color pageBg(Brightness b) => b == Brightness.dark ? pageBgDark : pageBgLight;
  static Color cardBg(Brightness b) => b == Brightness.dark ? cardBgDark : cardBgLight;
  static Color inputBg(Brightness b) => b == Brightness.dark ? inputBgDark : inputBgLight;
  static Color text(Brightness b) => b == Brightness.dark ? textDark : textLight;
  static Color textMuted(Brightness b) => b == Brightness.dark ? textMutedDark : textMutedLight;
  static Color border(Brightness b) => b == Brightness.dark ? borderDark : borderLight;
  static Color disabledBtn(Brightness b) => b == Brightness.dark ? disabledBtnDark : const Color(0xFFE2E8F0);
}
