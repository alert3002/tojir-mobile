import 'package:flutter/material.dart';

import 'permissions.dart';

class HomeCard {
  const HomeCard({
    required this.route,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String route;
  final String label;
  final IconData icon;
  final Color color;
}

const kActionCards = [
  HomeCard(route: '/sales', label: 'Продажа', icon: Icons.attach_money_rounded, color: Color(0xFF22C55E)),
  HomeCard(route: '/warehouse', label: 'Склад', icon: Icons.inbox_outlined, color: Color(0xFF0EA5E9)),
  HomeCard(route: '/returns', label: 'Возвраты', icon: Icons.keyboard_return_rounded, color: Color(0xFFF97316)),
  HomeCard(route: '/transfers', label: 'Перемещения', icon: Icons.swap_horiz_rounded, color: Color(0xFF0EA5E9)),
];

const kGridCards = [
  HomeCard(route: '/arrivals', label: 'Поступление', icon: Icons.add_circle_outline_rounded, color: Color(0xFF3B82F6)),
  HomeCard(route: '/clients', label: 'Клиенты', icon: Icons.groups_outlined, color: Color(0xFF0EA5E9)),
  HomeCard(route: '/debts', label: 'Долги', icon: Icons.account_balance_outlined, color: Color(0xFF64748B)),
  HomeCard(route: '/expenses', label: 'Расходы', icon: Icons.outbox_outlined, color: Color(0xFFA855F7)),
  HomeCard(route: '/stores', label: 'Магазины', icon: Icons.storefront_outlined, color: Color(0xFF3B82F6)),
  HomeCard(route: '/employees', label: 'Сотрудники', icon: Icons.person_outline_rounded, color: Color(0xFF6366F1)),
  HomeCard(route: '/tariffs', label: 'Тарифы', icon: Icons.workspace_premium_outlined, color: Color(0xFFFBBF24)),
];

const kExtraGridCards = [
  HomeCard(route: '/history', label: 'История', icon: Icons.history_rounded, color: Color(0xFF64748B)),
  HomeCard(route: '/referral', label: 'Реферал', icon: Icons.group_add_outlined, color: Color(0xFF6366F1)),
  HomeCard(route: '/course', label: 'Курс', icon: Icons.trending_up_rounded, color: Color(0xFF22C55E)),
];

const kReferralHomeCard = HomeCard(
  route: '/referral',
  label: 'Реферал',
  icon: Icons.group_add_outlined,
  color: Color(0xFF6366F1),
);

const kReportsCard = HomeCard(
  route: '/reports',
  label: 'Отчёт',
  icon: Icons.pie_chart_outline_rounded,
  color: Color(0xFF10B981),
);

const kClientHomeCards = [
  HomeCard(route: '/referral', label: 'Реферал', icon: Icons.group_add_outlined, color: Color(0xFF8B5CF6)),
  HomeCard(route: '/debts', label: 'Долги', icon: Icons.account_balance_outlined, color: Color(0xFF3B82F6)),
  HomeCard(route: '/history', label: 'История', icon: Icons.history_rounded, color: Color(0xFF64748B)),
  HomeCard(route: '/profile', label: 'Профиль', icon: Icons.person_outline_rounded, color: Color(0xFF3B82F6)),
];

const kSellerSecondaryOrder = [
  '/transfers',
  '/returns',
  '/clients',
  '/debts',
  '/referral',
  '/expenses',
  '/arrivals',
  '/history',
  '/course',
  '/reports',
  '/warehouse',
  '/employees',
  '/tariffs',
  '/stores',
];

const kSellerHints = <String, String>{
  '/returns': 'Возврат от клиента',
  '/transfers': 'Между магазинами',
  '/warehouse': 'Остатки товара',
  '/clients': 'Список покупателей',
  '/debts': 'Насия и долги',
  '/expenses': 'Расход магазина',
  '/history': 'Журнал операций',
  '/arrivals': 'Приём товара',
  '/referral': 'Пригласить друзей',
  '/profile': 'Баланс и настройки',
  '/course': 'Курс USD',
};

String? pathToSection(String path) {
  if (path == '/reports') return 'reports';
  if (path == '/sales') return 'sales';
  if (path == '/arrivals') return 'arrivals';
  if (path == '/returns') return 'returns';
  if (path == '/warehouse' || path.startsWith('/warehouse/')) return 'warehouse';
  if (path == '/transfers') return 'transfers';
  if (path == '/debts') return 'debts';
  if (path == '/expenses') return 'expenses';
  if (path == '/stores') return 'stores';
  if (path == '/employees' || path.startsWith('/employees/')) return 'employees';
  if (path == '/referral' || path.startsWith('/referral/')) return 'referral';
  if (path == '/tariffs' || path.startsWith('/tariffs/')) return 'tariffs';
  if (path == '/course' || path.startsWith('/course/')) return 'course';
  if (path == '/history') return 'history';
  if (path == '/clients' || path.startsWith('/clients/')) return 'sales';
  return null;
}

bool isClientLike(Map<String, dynamic>? user) {
  final role = user?['role'] as String?;
  if (role == 'client') return true;
  return role == 'moderator' && (user?['moderator_scope'] as String?) == 'business';
}

bool isBusinessmanHome(Map<String, dynamic>? user) {
  final role = user?['role'] as String?;
  return role == 'businessman' || role == 'platform';
}

List<HomeCard> filterCardsByAccess(Map<String, dynamic>? user, List<HomeCard> cards) {
  final perms = user?['allowed_perms'] as Map<String, dynamic>?;
  return cards.where((c) {
    final section = pathToSection(c.route);
    if (section == null) return true;
    final role = user?['role'] as String?;
    if (role == 'seller') {
      if (sellerMenuHiddenSectionKeys.contains(section)) return false;
      return sellerCanAccessSection(user!, section, perms);
    }
    if (role == 'nasiya') return nasiyaSectionKeys.contains(section);
    return canAccessSection(user, section, perms);
  }).toList();
}

List<HomeCard> getBusinessmanGridCards(Map<String, dynamic>? user) {
  return filterCardsByAccess(user, [
    ...kActionCards,
    kReportsCard,
    ...kGridCards,
    ...kExtraGridCards,
  ]);
}

List<HomeCard> getNasiyaGridCards(Map<String, dynamic>? user) {
  return filterCardsByAccess(user, [
    ...kActionCards,
    ...kGridCards,
    ...kExtraGridCards.where((c) => c.route == '/history' || c.route == '/referral'),
  ]);
}

List<HomeCard> getDefaultGridCards(Map<String, dynamic>? user) {
  return filterCardsByAccess(user, [...kActionCards, ...kGridCards]);
}

List<HomeCard> getClientHomeCards(Map<String, dynamic>? user) {
  return filterCardsByAccess(user, kClientHomeCards);
}

List<HomeCard> mergeSellerSecondaryCards(List<HomeCard> quick, List<HomeCard> more, [List<HomeCard> extra = const []]) {
  final byPath = <String, HomeCard>{};
  for (final card in [...quick, ...more, ...extra]) {
    if (card.route != '/sales') byPath[card.route] = card;
  }
  final order = {for (var i = 0; i < kSellerSecondaryOrder.length; i++) kSellerSecondaryOrder[i]: i};
  final list = byPath.values.toList()
    ..sort((a, b) {
      final ai = order[a.route] ?? 999;
      final bi = order[b.route] ?? 999;
      return ai.compareTo(bi);
    });
  return list;
}

List<HomeCard> getSellerSecondaryCards(Map<String, dynamic>? user) {
  final actions = filterCardsByAccess(user, kActionCards).where((c) => c.route != '/sales').toList();
  final grid = filterCardsByAccess(user, kGridCards);
  return mergeSellerSecondaryCards(actions, grid, [kReferralHomeCard]);
}

HomeCard? getSellerSalesCard(Map<String, dynamic>? user) {
  final cards = filterCardsByAccess(user, kActionCards);
  for (final c in cards) {
    if (c.route == '/sales') return c;
  }
  return null;
}

String sellerDisplayName(Map<String, dynamic>? user) {
  if (user == null) return 'Продавец';
  final fn = (user['first_name'] as String?)?.trim() ?? '';
  final ln = (user['last_name'] as String?)?.trim() ?? '';
  final full = '$fn $ln'.trim();
  if (full.isNotEmpty) return full;
  return (user['phone'] as String?) ?? 'Продавец';
}

String? sellerOutletText(Map<String, dynamic>? user) {
  if (user == null) return null;
  final names = user['allowed_outlet_names'];
  if (names is List && names.isNotEmpty) {
    final first = names.first.toString();
    if (names.length == 1) return first;
    return '$first +${names.length - 1}';
  }
  final wh = user['warehouse_name'];
  if (wh != null && wh.toString().trim().isNotEmpty) return wh.toString();
  return null;
}

String sellerCardTone(String route) {
  const tones = {
    '/warehouse': 'sky',
    '/returns': 'orange',
    '/transfers': 'cyan',
    '/clients': 'blue',
    '/debts': 'rose',
    '/expenses': 'purple',
    '/arrivals': 'indigo',
    '/history': 'slate',
    '/referral': 'violet',
    '/course': 'green',
    '/reports': 'emerald',
    '/stores': 'blue',
    '/employees': 'indigo',
    '/tariffs': 'amber',
    '/profile': 'blue',
  };
  return tones[route] ?? 'blue';
}

List<Color> sellerToneGradient(String tone) {
  switch (tone) {
    case 'sky':
      return const [Color(0xFF0284C7), Color(0xFF0369A1)];
    case 'orange':
      return const [Color(0xFFF97316), Color(0xFFEA580C)];
    case 'cyan':
      return const [Color(0xFF06B6D4), Color(0xFF0891B2)];
    case 'rose':
      return const [Color(0xFFF43F5E), Color(0xFFE11D48)];
    case 'purple':
      return const [Color(0xFFA855F7), Color(0xFF9333EA)];
    case 'indigo':
      return const [Color(0xFF6366F1), Color(0xFF4F46E5)];
    case 'slate':
      return const [Color(0xFF64748B), Color(0xFF475569)];
    case 'violet':
      return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
    case 'green':
      return const [Color(0xFF22C55E), Color(0xFF16A34A)];
    case 'emerald':
      return const [Color(0xFF10B981), Color(0xFF059669)];
    case 'amber':
      return const [Color(0xFFF59E0B), Color(0xFFD97706)];
    case 'blue':
    default:
      return const [Color(0xFF3B82F6), Color(0xFF2563EB)];
  }
}

String? formatDebtBadgeAmounts(List<Map<String, dynamic>> lines, bool negative) {
  if (lines.isEmpty) return null;
  final sign = negative ? '−' : '+';
  return lines.map((x) {
    final raw = x['amount'];
    final n = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
    return '$sign${n.round()}';
  }).join(' · ');
}
