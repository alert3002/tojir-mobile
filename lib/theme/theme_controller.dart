import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _kTheme = 'tojir_theme_mode'; // light|dark

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = (p.getString(_kTheme) ?? '').toLowerCase().trim();
    _mode = raw == 'light' ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, _mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}

