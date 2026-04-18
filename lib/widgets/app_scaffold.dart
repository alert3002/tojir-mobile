import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../theme/app_shape.dart';
import '../theme/theme_controller.dart';
import '../utils/permissions.dart';
import 'app_bottom_nav.dart';
import 'app_header.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.showBottomNav = true,
  });

  final Widget child;
  final bool showBottomNav;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: dark ? cs.surface : Theme.of(context).scaffoldBackgroundColor,
      drawer: const _AppDrawer(),
      body: Column(
        children: [
          Builder(
            builder: (ctx) => AppHeader(
              onMenuTap: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: showBottomNav ? AppBottomNav(user: user) : null,
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  static const _logoutRed = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = context.watch<ThemeController>().mode;
    final isDarkMode = themeMode == ThemeMode.dark;

    final bg = dark ? const Color(0xFF121A28) : const Color(0xFFF8FAFC);
    final onDrawer = dark ? Colors.white : const Color(0xFF0F172A);
    final muted = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final iconColor = dark ? Colors.white : const Color(0xFF334155);

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: onDrawer, size: 26),
                      tooltip: 'Закрыть',
                    ),
                  ),
                  Image.asset(
                    'assets/images/tojir_logo.png',
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      'Tojir',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: onDrawer),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Настройки',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: muted,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            _DrawerSettingsTile(
              icon: isDarkMode ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              label: isDarkMode ? 'Светлая тема' : 'Тёмная тема',
              iconColor: iconColor,
              textColor: onDrawer,
              onTap: () => context.read<ThemeController>().toggle(),
            ),
            _DrawerSettingsTile(
              icon: Icons.notifications_none_rounded,
              label: 'Уведомления (push)',
              iconColor: iconColor,
              textColor: onDrawer,
              onTap: () {
                final u = context.read<SessionController>().user;
                if (u != null &&
                    (u['role'] as String?) == 'businessman' &&
                    !businessmanHasWarehouse(u)) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сначала укажите склад в профиле.')),
                  );
                  return;
                }
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/settings/notifications');
              },
            ),
            _DrawerSettingsTile(
              icon: Icons.person_outline_rounded,
              label: 'Профиль и баланс',
              iconColor: iconColor,
              textColor: onDrawer,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil('/profile', (r) => r.isFirst);
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await context.read<SessionController>().logout();
                  if (!context.mounted) return;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _logoutRed,
                  side: const BorderSide(color: _logoutRed, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppShape.br),
                ),
                icon: const Icon(Icons.logout_rounded, size: 20, color: _logoutRed),
                label: const Text(
                  'Выход',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _logoutRed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSettingsTile extends StatelessWidget {
  const _DrawerSettingsTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

