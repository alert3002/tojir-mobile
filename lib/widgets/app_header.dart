import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../theme/app_brand.dart';
import '../utils/permissions.dart';
import '../utils/platform_info.dart';
import 'tojir_logo.dart';

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

  bool _subscriptionLocked(Map<String, dynamic>? user) {
    if (user == null) return false;
    final role = user['role'] as String?;
    if (role == 'businessman' || role == 'seller') {
      return user['subscription_is_expired'] == true;
    }
    if (role == 'moderator' && user['moderator_scope'] == 'business') {
      return user['subscription_is_expired'] == true;
    }
    return false;
  }

  bool _subscriptionWarn(Map<String, dynamic>? user) {
    if (user == null) return false;
    final role = user['role'] as String?;
    if (role == 'businessman' || role == 'seller') {
      return user['subscription_warn'] == true;
    }
    if (role == 'moderator' && user['moderator_scope'] == 'business') {
      return user['subscription_warn'] == true;
    }
    return false;
  }

  int? _subscriptionDaysLeft(Map<String, dynamic>? user) {
    final v = user?['subscription_days_left'];
    if (v is num) return v.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final session = context.watch<SessionController>();
    final user = session.user;
    final bal = _balanceText(user);
    final subLocked = _subscriptionLocked(user);
    final subWarn = !subLocked && _subscriptionWarn(user);
    final daysLeft = _subscriptionDaysLeft(user);

    final topInset = MediaQuery.of(context).padding.top;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;
    final iconColor = dark ? AppBrand.textMutedDark : cs.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.fromLTRB(8, topInset + 2, 8, 0),
      decoration: BoxDecoration(
        color: pageBg,
        border: Border(
          bottom: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 4),
            TojirLogo(height: 26, dark: dark),
            _HeaderIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Меню',
              color: iconColor,
              onTap: onMenuTap ?? () {},
            ),
            const Spacer(),
            if (subLocked)
              _SubscriptionPill(
                label: 'Подписка истекла',
                locked: true,
                onTap: () => Navigator.of(context).pushNamed('/tariffs'),
              )
            else if (subWarn)
              _SubscriptionPill(
                label: 'Осталось ${(daysLeft ?? 0).clamp(0, 999)} дн.',
                locked: false,
                onTap: () => Navigator.of(context).pushNamed('/tariffs'),
              ),
            _HeaderIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Уведомления',
              color: iconColor,
              onTap: () {
                if (user != null &&
                    (user['role'] as String?) == 'businessman' &&
                    !businessmanHasWarehouse(user)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сначала укажите склад в профиле.')),
                  );
                  return;
                }
                Navigator.of(context).pushNamed('/settings/notifications');
              },
            ),
            if (!isIosApp)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamed('/profile'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        '$bal TJS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
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

class _SubscriptionPill extends StatelessWidget {
  const _SubscriptionPill({required this.label, required this.locked, required this.onTap});

  final String label;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = locked ? const Color(0xFFFB7185) : const Color(0xFFFBBF24);
    final bg = locked ? const Color(0xFFFB7185).withValues(alpha: 0.12) : const Color(0xFFFBBF24).withValues(alpha: 0.12);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
