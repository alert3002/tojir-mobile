import 'package:flutter/material.dart';

import 'permissions.dart';

class DrawerMenuItem {
  const DrawerMenuItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.sectionKey,
  });

  final String route;
  final String label;
  final IconData icon;
  final String sectionKey;
}

const _sectionItems = <DrawerMenuItem>[
  DrawerMenuItem(route: '/sales', label: 'Продажа', icon: Icons.shopping_cart_outlined, sectionKey: 'sales'),
  DrawerMenuItem(route: '/warehouse', label: 'Склад', icon: Icons.inventory_2_outlined, sectionKey: 'warehouse'),
  DrawerMenuItem(route: '/debts', label: 'Долги (Насия)', icon: Icons.attach_money_rounded, sectionKey: 'debts'),
  DrawerMenuItem(route: '/reports', label: 'Отчёт', icon: Icons.pie_chart_outline_rounded, sectionKey: 'reports'),
  DrawerMenuItem(route: '/history', label: 'История', icon: Icons.history_rounded, sectionKey: 'history'),
  DrawerMenuItem(route: '/referral', label: 'Реферал', icon: Icons.group_add_outlined, sectionKey: 'referral'),
  DrawerMenuItem(route: '/tariffs', label: 'Тарифы', icon: Icons.workspace_premium_outlined, sectionKey: 'tariffs'),
];

const _essentialOrder = <String, List<String>>{
  'businessman': ['sales', 'warehouse', 'debts', 'reports', 'history'],
  'platform': ['sales', 'warehouse', 'debts', 'history'],
  'seller': ['sales', 'warehouse', 'debts', 'history', 'referral'],
  'client': ['debts', 'history', 'referral'],
  'nasiya': ['sales', 'debts', 'history', 'referral'],
};

bool subscriptionLocked(Map<String, dynamic>? user) {
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

bool subscriptionWarn(Map<String, dynamic>? user) {
  if (user == null) return false;
  final role = user['role'] as String?;
  if (role != 'businessman' && role != 'seller') {
    if (role == 'moderator' && (user['moderator_scope'] as String?) == 'business') {
      return user['subscription_warn'] == true;
    }
    return false;
  }
  return user['subscription_warn'] == true;
}

String resolveMenuRole(Map<String, dynamic>? user) {
  if (user == null) return 'client';
  final role = user['role'] as String?;
  if (role == 'moderator' && (user['moderator_scope'] as String?) == 'business') return 'client';
  if (role == 'moderator' && (user['moderator_scope'] as String?) == 'platform') return 'platform';
  return role ?? 'client';
}

String getRoleLabel(Map<String, dynamic>? user) {
  if (user == null) return 'Пользователь';
  final role = user['role'] as String?;
  if (role == 'moderator') {
    return (user['moderator_scope'] as String?) == 'platform' ? 'Модератор платформы' : 'Клиент';
  }
  const map = {
    'businessman': 'Бизнесмен',
    'seller': 'Продавец',
    'client': 'Клиент',
    'nasiya': 'Насия',
    'platform': 'Платформа',
  };
  return map[role] ?? 'Пользователь';
}

List<DrawerMenuItem> _filterByRole(Map<String, dynamic>? user) {
  if (user == null) return const [];
  final perms = user['allowed_perms'] as Map<String, dynamic>?;
  return _sectionItems.where((it) => canAccessSection(user, it.sectionKey, perms)).toList();
}

List<DrawerMenuItem> getDrawerSectionItems(Map<String, dynamic>? user) {
  final role = resolveMenuRole(user);
  final order = _essentialOrder[role] ?? _essentialOrder['businessman']!;
  final allowed = Set<String>.from(order);
  if (subscriptionLocked(user) || subscriptionWarn(user)) {
    allowed.add('tariffs');
  }

  final filtered = _filterByRole(user).where((it) => allowed.contains(it.sectionKey)).toList();
  final byKey = {for (final it in filtered) it.sectionKey: it};
  final ordered = order.map((k) => byKey[k]).whereType<DrawerMenuItem>().toList();
  if ((subscriptionLocked(user) || subscriptionWarn(user)) && byKey['tariffs'] != null) {
    if (!ordered.any((it) => it.sectionKey == 'tariffs')) {
      ordered.add(byKey['tariffs']!);
    }
  }
  if (resolveMenuRole(user) == 'client') {
    return ordered
        .map(
          (it) => it.sectionKey == 'debts'
              ? const DrawerMenuItem(
                  route: '/debts',
                  label: 'Долги',
                  icon: Icons.attach_money_rounded,
                  sectionKey: 'debts',
                )
              : it,
        )
        .toList();
  }
  return ordered;
}

String? drawerSelectedRoute(String? currentRoute) {
  final p = currentRoute ?? '/';
  if (p == '/') return '/';
  const keys = [
    '/',
    '/sales',
    '/warehouse',
    '/debts',
    '/reports',
    '/history',
    '/referral',
    '/tariffs',
    '/settings/notifications',
    '/profile',
  ];
  final sorted = keys.where((k) => k != '/').toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in sorted) {
    if (p == k || p.startsWith('$k/')) return k;
  }
  return p;
}

String drawerRedirectRoute(Map<String, dynamic>? user, String route) {
  if ((user?['role'] as String?) == 'businessman' && !businessmanHasWarehouse(user)) {
    return '/profile';
  }
  if (subscriptionLocked(user) && route != '/tariffs') {
    return '/tariffs';
  }
  return route;
}
