import 'package:flutter/material.dart';

import '../theme/app_brand.dart';
import '../utils/bottom_nav_items.dart';

/// Нижняя навигация — как web `.tojir-bottom-nav` (плоская, 64px, full width).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.user});

  final Map<String, dynamic>? user;

  int _selectedIndex(String? route, List<BottomNavItem> items) {
    final r = route ?? '/';
    final idx = items.indexWhere((x) => x.route == r);
    if (idx >= 0) return idx;
    for (final prefix in ['/warehouse', '/sales', '/history', '/reports', '/debts', '/referral', '/profile']) {
      if (r.startsWith(prefix)) {
        final i = items.indexWhere((x) => x.route == prefix);
        if (i >= 0) return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final items = getBottomNavItems(user);
    final route = ModalRoute.of(context)?.settings.name;
    final selected = _selectedIndex(route, items);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppBrand.darkPage : Colors.white;
    final borderColor = dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    return Material(
      color: bg,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: Border(top: BorderSide(color: borderColor)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppBrand.bottomNavHeight,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _BottomNavItem(
                      item: items[i],
                      active: i == selected,
                      locked: bottomNavItemLocked(user, items[i]),
                      dark: dark,
                      onTap: () {
                        final item = items[i];
                        final to = bottomNavItemLocked(user, item)
                            ? bottomNavRedirectRoute(user, item)
                            : (item.route ?? '/');
                        if (item.route == null) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          return;
                        }
                        if (to == route) return;
                        Navigator.of(context).pushNamedAndRemoveUntil(to, (r) => r.isFirst);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.item,
    required this.active,
    required this.locked,
    required this.dark,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool active;
  final bool locked;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = dark ? AppBrand.textMutedDark : const Color(0xFF475569);
    final activeColor = dark ? AppBrand.navActiveDark : AppBrand.primaryBlue;
    final fg = active ? activeColor : inactive.withValues(alpha: locked ? 0.45 : 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  height: 1.15,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
