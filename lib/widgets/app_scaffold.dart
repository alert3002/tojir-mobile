import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../utils/drawer_menu_items.dart';
import '../utils/permissions.dart';
import 'app_bottom_nav.dart';
import 'app_header.dart';
import 'low_stock_banner.dart';
import 'tojir_logo.dart';

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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: _AppDrawer(user: user),
      body: Column(
        children: [
          Builder(
            builder: (ctx) => AppHeader(
              onMenuTap: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          LowStockBanner(user: user),
          Expanded(
            child: Padding(
              padding: showBottomNav
                  ? const EdgeInsets.only(bottom: 4)
                  : EdgeInsets.zero,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: showBottomNav ? AppBottomNav(user: user) : null,
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.user});

  static const _drawerBg = Color(0xFF0C111C);
  static const _logoutRed = Color(0xFFFF4D4F);

  final Map<String, dynamic>? user;

  String _displayName(SessionController session) {
    final u = user;
    if (u == null) return 'Пользователь';
    final fn = (u['first_name'] as String?)?.trim() ?? '';
    final ln = (u['last_name'] as String?)?.trim() ?? '';
    final full = '$fn $ln'.trim();
    if (full.isNotEmpty) return full;
    return (u['phone'] as String?) ?? 'Пользователь';
  }

  double? _balance() {
    final v = user?['balance'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pop();
    final to = drawerRedirectRoute(user, route);
    if (to == '/') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final current = ModalRoute.of(context)?.settings.name;
    if (current == to) return;
    Navigator.of(context).pushNamedAndRemoveUntil(to, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final warehouseLocked = (user?['role'] as String?) == 'businessman' && !businessmanHasWarehouse(user);
    final currentRoute = drawerSelectedRoute(ModalRoute.of(context)?.settings.name);
    final menuRole = resolveMenuRole(user);
    final roleLabel = getRoleLabel(user);
    final sectionItems = warehouseLocked ? const <DrawerMenuItem>[] : getDrawerSectionItems(user);
    final balance = _balance();
    final showBalance = (user?['role'] == 'businessman' || user?['role'] == 'seller') && balance != null;

    return Drawer(
      width: 300,
      backgroundColor: _drawerBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    tooltip: 'Закрыть',
                  ),
                  const SizedBox(width: 2),
                  _DrawerBrand(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1F2563EB), Color(0x002563EB)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      ),
                    ),
                    child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _RoleBadge(label: roleLabel, menuRole: menuRole),
                        if (showBalance) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${balance.toStringAsFixed(2)} TJS',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF86EFAC),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _DrawerNavTile(
                    icon: Icons.home_outlined,
                    label: 'Главная',
                    selected: currentRoute == '/',
                    onTap: () => _navigate(context, warehouseLocked ? '/profile' : '/'),
                  ),
                  for (final item in sectionItems)
                    _DrawerNavTile(
                      icon: item.icon,
                      label: item.label,
                      selected: currentRoute == item.route,
                      onTap: () => _navigate(context, item.route),
                    ),
                  const _DrawerGroupDivider(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      'НАСТРОЙКИ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.66,
                        color: Color(0x73FFFFFF),
                      ),
                    ),
                  ),
                  _DrawerNavTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Уведомления',
                    selected: currentRoute == '/settings/notifications',
                    onTap: () {
                      if (warehouseLocked) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Сначала укажите склад в профиле.')),
                        );
                        return;
                      }
                      _navigate(context, '/settings/notifications');
                    },
                  ),
                  _DrawerNavTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Профиль и баланс',
                    selected: currentRoute == '/profile',
                    onTap: () => _navigate(context, '/profile'),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
              ),
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await context.read<SessionController>().logout();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _logoutRed,
                    side: const BorderSide(color: _logoutRed),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18, color: _logoutRed),
                  label: const Text(
                    'Выход',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _logoutRed),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TojirLogo(height: 28, dark: true),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, required this.menuRole});

  final String label;
  final String menuRole;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (menuRole) {
      'businessman' => (const Color(0xFF86EFAC), const Color(0x2622C55E)),
      'seller' => (const Color(0xFF93C5FD), const Color(0x2E2563EB)),
      'client' => (const Color(0xFFC4B5FD), const Color(0x2E8B5CF6)),
      'nasiya' => (const Color(0xFFFCD34D), const Color(0x2EF59E0B)),
      _ => (const Color(0xFF94A3B8), const Color(0x2694A3B8)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.6),
      ),
    );
  }
}

class _DrawerGroupDivider extends StatelessWidget {
  const _DrawerGroupDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? const Color(0x382563EB) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected ? Border.all(color: Colors.white.withValues(alpha: 0.18)) : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: Colors.white.withValues(alpha: selected ? 1 : 0.88)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: Colors.white.withValues(alpha: selected ? 1 : 0.92),
                    ),
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
