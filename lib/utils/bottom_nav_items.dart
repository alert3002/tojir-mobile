import 'package:flutter/material.dart';

import 'permissions.dart';

class BottomNavItem {
  const BottomNavItem({
    required this.label,
    this.icon,
    required this.route,
    this.sectionKey,
    this.isSupport = false,
  }) : assert(isSupport || icon != null);

  final String label;
  final IconData? icon;
  final String? route;
  final String? sectionKey;
  final bool isSupport;
}

bool _subscriptionLocked(Map<String, dynamic>? user) {
  if (user == null) return false;
  final role = user['role'] as String?;
  if (role != 'businessman' && role != 'seller') {
    if (role == 'moderator' && (user['moderator_scope'] as String?) == 'business') {
      return user['subscription_is_expired'] == true;
    }
    return false;
  }
  return user['subscription_is_expired'] == true;
}

bool _clientLike(Map<String, dynamic>? user) {
  final role = user?['role'] as String?;
  if (role == 'client') return true;
  return role == 'moderator' && (user?['moderator_scope'] as String?) == 'business';
}

const _sellerBottom = [
  BottomNavItem(label: 'Главная', icon: Icons.home_rounded, route: null),
  BottomNavItem(label: 'Продажа', icon: Icons.shopping_cart_outlined, route: '/sales', sectionKey: 'sales'),
  BottomNavItem(label: 'Склад', icon: Icons.inventory_2_outlined, route: '/warehouse', sectionKey: 'warehouse'),
  BottomNavItem(label: 'История', icon: Icons.history_rounded, route: '/history', sectionKey: 'history'),
  BottomNavItem(label: 'Техподдержка', route: '/support', isSupport: true),
  BottomNavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
];

const _businessmanBottom = [
  BottomNavItem(label: 'Главная', icon: Icons.home_rounded, route: null),
  BottomNavItem(label: 'Продажа', icon: Icons.shopping_cart_outlined, route: '/sales', sectionKey: 'sales'),
  BottomNavItem(label: 'Отчёт', icon: Icons.pie_chart_outline_rounded, route: '/reports', sectionKey: 'reports'),
  BottomNavItem(label: 'История', icon: Icons.history_rounded, route: '/history', sectionKey: 'history'),
  BottomNavItem(label: 'Техподдержка', route: '/support', isSupport: true),
  BottomNavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
];

const _clientBottom = [
  BottomNavItem(label: 'Главная', icon: Icons.home_rounded, route: null),
  BottomNavItem(label: 'Долги', icon: Icons.account_balance_outlined, route: '/debts', sectionKey: 'debts'),
  BottomNavItem(label: 'История', icon: Icons.history_rounded, route: '/history', sectionKey: 'history'),
  BottomNavItem(label: 'Реферал', icon: Icons.group_add_outlined, route: '/referral', sectionKey: 'referral'),
  BottomNavItem(label: 'Техподдержка', route: '/support', isSupport: true),
  BottomNavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
];

const _nasiyaBottom = [
  BottomNavItem(label: 'Главная', icon: Icons.home_rounded, route: null),
  BottomNavItem(label: 'Продажа', icon: Icons.shopping_cart_outlined, route: '/sales', sectionKey: 'sales'),
  BottomNavItem(label: 'Долги', icon: Icons.account_balance_outlined, route: '/debts', sectionKey: 'debts'),
  BottomNavItem(label: 'История', icon: Icons.history_rounded, route: '/history', sectionKey: 'history'),
  BottomNavItem(label: 'Техподдержка', route: '/support', isSupport: true),
  BottomNavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
];

List<BottomNavItem> getBottomNavItems(Map<String, dynamic>? user) {
  if (user == null) return _clientBottom;

  if ((user['role'] as String?) == 'businessman' && !businessmanHasWarehouse(user)) {
    return const [
      BottomNavItem(label: 'Техподдержка', route: '/support', isSupport: true),
      BottomNavItem(label: 'Профиль', icon: Icons.person_rounded, route: '/profile'),
    ];
  }

  if (_clientLike(user)) return _clientBottom;
  if ((user['role'] as String?) == 'nasiya') return _nasiyaBottom;

  if ((user['role'] as String?) == 'seller') {
    final perms = user['allowed_perms'] as Map<String, dynamic>?;
    return _sellerBottom.where((it) {
      if (it.sectionKey == null) return true;
      return sellerCanAccessSection(user, it.sectionKey!, perms);
    }).toList();
  }

  return _businessmanBottom;
}

bool bottomNavItemLocked(Map<String, dynamic>? user, BottomNavItem item) {
  if (user == null) return false;
  if ((user['role'] as String?) == 'businessman' && !businessmanHasWarehouse(user)) {
    return item.route != '/profile' && item.route != '/support';
  }
  if (_subscriptionLocked(user)) {
    return item.route != '/profile' &&
        item.route != '/tariffs' &&
        item.route != '/support' &&
        item.route != null;
  }
  return false;
}

String bottomNavRedirectRoute(Map<String, dynamic>? user, BottomNavItem item) {
  if ((user?['role'] as String?) == 'businessman' && !businessmanHasWarehouse(user)) {
    return '/profile';
  }
  if (_subscriptionLocked(user)) return '/tariffs';
  return item.route ?? '/';
}
