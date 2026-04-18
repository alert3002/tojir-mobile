import 'package:flutter/material.dart';

import '../utils/permissions.dart';

bool _businessmanLocked(Map<String, dynamic>? u) =>
    u != null && (u['role'] as String?) == 'businessman' && !businessmanHasWarehouse(u);

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.user});

  final Map<String, dynamic>? user;

  static const _h = 68.0;

  static const _items = <_NavItem>[
    _NavItem(label: 'Главная', icon: Icons.home_rounded, route: null),
    _NavItem(label: 'Товары', icon: Icons.inventory_2_rounded, route: '/warehouse', sectionKey: 'warehouse'),
    _NavItem(label: 'Продажа', icon: Icons.attach_money_rounded, route: '/sales', sectionKey: 'sales'),
    _NavItem(label: 'История', icon: Icons.history_rounded, route: '/history', sectionKey: 'history'),
    _NavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
  ];

  List<_NavItem> _visibleItems() {
    final u = user;
    if (u == null) return _items;
    if (_businessmanLocked(u)) {
      return _items.where((it) => it.route == '/profile').toList();
    }
    return _items.where((it) {
      if (it.sectionKey == null) return true;
      return canAccessSection(u, it.sectionKey!, null);
    }).toList();
  }

  int _selectedIndex(String? route, List<_NavItem> items) {
    final r = route ?? '/';
    final idx = items.indexWhere((x) => x.route == r);
    if (idx >= 0) return idx;
    // group: treat many screens as "Главная"
    if (r.startsWith('/warehouse')) return items.indexWhere((x) => x.route == '/warehouse').clamp(0, items.length - 1);
    if (r.startsWith('/sales')) return items.indexWhere((x) => x.route == '/sales').clamp(0, items.length - 1);
    if (r.startsWith('/history')) return items.indexWhere((x) => x.route == '/history').clamp(0, items.length - 1);
    if (r.startsWith('/profile')) return items.indexWhere((x) => x.route == '/profile').clamp(0, items.length - 1);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems();
    final route = ModalRoute.of(context)?.settings.name;
    final selected = _selectedIndex(route, items);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          elevation: dark ? 6 : 10,
          shadowColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
          borderRadius: BorderRadius.circular(18),
          color: dark ? cs.surfaceContainer.withValues(alpha: 0.92) : cs.surface,
          child: Container(
            height: _h,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.55)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _BottomNavItem(
                      item: items[i],
                      active: i == selected,
                      onTap: () {
                        final to = items[i].route;
                        if (to == null) {
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
  const _BottomNavItem({required this.item, required this.active, required this.onTap});

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = active ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.88);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active ? cs.primaryContainer.withValues(alpha: dark ? 0.55 : 0.75) : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 22, color: fg),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.1,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon, required this.route, this.sectionKey});
  final String label;
  final IconData icon;
  final String? route;
  final String? sectionKey;
}

