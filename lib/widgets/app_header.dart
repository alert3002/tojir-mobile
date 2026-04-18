import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../theme/app_shape.dart';
import '../theme/theme_controller.dart';
import '../utils/permissions.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.onMenuTap});

  final VoidCallback? onMenuTap;

  String _balanceText(Map<String, dynamic>? user) {
    final v = user?['balance'];
    double? n;
    if (v is num) n = v.toDouble();
    if (v is String) n = double.tryParse(v);
    if (n == null) return '—';
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final session = context.watch<SessionController>();
    final user = session.user;
    final bal = _balanceText(user);

    const extraTop = 25.0;
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(12, topInset + extraTop, 14, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [cs.surface.withValues(alpha: 0.001), cs.surfaceContainer.withValues(alpha: 0.25)]
              : [Theme.of(context).scaffoldBackgroundColor, Theme.of(context).scaffoldBackgroundColor],
        ),
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.5),
          ),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _HeaderIcon(
                  tooltip: 'Меню',
                  icon: Icons.menu_rounded,
                  onTap: onMenuTap ?? () {},
                ),
                const SizedBox(width: 10),
                Image.asset(
                  'assets/images/tojir_logo.png',
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    'Tojir',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.2,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: AppShape.br,
                    gradient: LinearGradient(
                      colors: [
                        cs.primaryContainer.withValues(alpha: dark ? 0.45 : 0.85),
                        cs.tertiaryContainer.withValues(alpha: dark ? 0.25 : 0.5),
                      ],
                    ),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: dark ? 0.12 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    '$bal TJS',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.2,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _HeaderIcon(
                  tooltip: 'Уведомления',
                  icon: Icons.notifications_none_rounded,
                  onTap: () {
                    final u = context.read<SessionController>().user;
                    if (u != null &&
                        (u['role'] as String?) == 'businessman' &&
                        !businessmanHasWarehouse(u)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Сначала укажите склад в профиле.')),
                      );
                      return;
                    }
                    Navigator.of(context).pushNamed('/settings/notifications');
                  },
                ),
                const SizedBox(width: 8),
                _HeaderIcon(
                  tooltip: dark ? 'Светлая тема' : 'Тёмная тема',
                  icon: dark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                  onTap: () => context.read<ThemeController>().toggle(),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: dark ? 0.4 : 0.65),
        borderRadius: AppShape.br,
        child: InkWell(
          borderRadius: AppShape.br,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

