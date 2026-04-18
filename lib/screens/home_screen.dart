import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double? usdToTjs;
  List<Map<String, dynamic>> weOwe = const [];
  List<Map<String, dynamic>> clientOwes = const [];

  bool _loadingRate = false;
  bool _loadingDebts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadRate(), _loadDebtTotals()]);
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _clientLike {
    final u = _user;
    final role = u?['role'] as String?;
    if (role == 'client') return true;
    if (role == 'moderator' && (u?['moderator_scope'] as String?) == 'business') return true;
    return false;
  }

  Future<void> _loadRate() async {
    final u = _user;
    if (u == null) return;
    if (!canAccessSection(u, 'course', null)) return;
    setState(() => _loadingRate = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final v = d['usd_to_tjs'];
        final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        setState(() => usdToTjs = (n != null && n > 0) ? n : null);
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingRate = false);
    }
  }

  Future<void> _loadDebtTotals() async {
    final u = _user;
    if (u == null || _clientLike) return;
    if (!canAccessSection(u, 'debts', null)) return;
    setState(() => _loadingDebts = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.get('inventory/debts/totals-badge/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final we = d['we_owe'];
        final co = d['client_owes'];
        setState(() {
          weOwe = (we is List) ? we.cast<Map<String, dynamic>>() : const [];
          clientOwes = (co is List) ? co.cast<Map<String, dynamic>>() : const [];
        });
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingDebts = false);
    }
  }

  String? _formatDebtBadgeAmounts(List<Map<String, dynamic>> lines, bool negative) {
    if (lines.isEmpty) return null;
    final sign = negative ? '−' : '+';
    return lines.map((x) => '$sign${x['amount']}').join(' ');
  }

  void _go(String route) {
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final u = session.user ?? const <String, dynamic>{};
    final role = (u['role'] as String?) ?? '—';

    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final actionCards = <_ActionCard>[
      _ActionCard('/sales', 'Продажа', Icons.attach_money_rounded, const Color(0xFF22C55E)),
      _ActionCard('/arrivals', 'Поступление', Icons.add_circle_outline_rounded, const Color(0xFF3B82F6)),
      _ActionCard('/returns', 'Возвраты', Icons.keyboard_return_rounded, const Color(0xFFF97316)),
      _ActionCard('/transfers', 'Перемещения', Icons.swap_horiz_rounded, const Color(0xFF0EA5E9)),
    ];

    final gridCardsBase = <_GridCard>[
      _GridCard('/warehouse', 'Товары', Icons.inventory_2_outlined, const Color(0xFF0EA5E9)),
      _GridCard('/clients', 'Клиенты', Icons.groups_outlined, const Color(0xFF0EA5E9)),
      _GridCard('/debts', 'Долги', Icons.account_balance_outlined, const Color(0xFF64748B)),
      _GridCard('/expenses', 'Расходы', Icons.outbox_outlined, const Color(0xFFA855F7)),
      _GridCard('/stores', 'Магазины', Icons.storefront_outlined, const Color(0xFF3B82F6)),
      _GridCard('/employees', 'Сотрудники', Icons.person_outline_rounded, const Color(0xFF6366F1)),
      _GridCard('/tariffs', 'Тарифы', Icons.workspace_premium_outlined, const Color(0xFFFBBF24)),
    ];

    List<_ActionCard> visibleActions = actionCards;
    if (role == 'seller') {
      visibleActions = actionCards.where((c) {
        final section = _pathToSection(c.to);
        return section != null && sellerCanAccessSection(u, section, null);
      }).toList();
    } else {
      visibleActions = actionCards.where((c) {
        final section = _pathToSection(c.to);
        return section != null && canAccessSection(u, section, null);
      }).toList();
    }

    List<_GridCard> visibleGrid;
    if (role == 'seller') {
      visibleGrid = gridCardsBase.where((c) {
        final section = _pathToSection(c.to);
        if (section == null) return false;
        if (sellerMenuHiddenSectionKeys.contains(section)) return false;
        return sellerCanAccessSection(u, section, null);
      }).toList();
    } else if (role == 'businessman') {
      final withReports = [
        _GridCard('/reports', 'Отчёт', Icons.pie_chart_outline_rounded, const Color(0xFF10B981)),
        ...gridCardsBase,
      ];
      visibleGrid = withReports.where((c) {
        final section = _pathToSection(c.to);
        if (section == null) return false;
        return canAccessSection(u, section, null);
      }).toList();
    } else {
      visibleGrid = gridCardsBase.where((c) {
        final section = _pathToSection(c.to);
        if (section == null) return false;
        return canAccessSection(u, section, null);
      }).toList();
    }

    if (_clientLike) {
      return AppScaffold(
        child: SafeArea(
          top: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _go('/referral'),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Реферальная программа'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => _go('/profile'),
                    child: const Text('Профиль и баланс'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final debtWe = _formatDebtBadgeAmounts(weOwe, true);
    final debtCo = _formatDebtBadgeAmounts(clientOwes, false);

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              if (canAccessSection(u, 'course', null))
                _RatePill(
                  loading: _loadingRate,
                  value: usdToTjs,
                  onTap: () => _go('/course'),
                ),
              const SizedBox(height: 14),
              ...visibleActions.map((c) => _ActionTile(card: c, onTap: () => _go(c.to))),
              const SizedBox(height: 6),
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.05,
                ),
                itemCount: visibleGrid.length,
                itemBuilder: (ctx, i) {
                  final g = visibleGrid[i];
                  final isDebts = g.to == '/debts' && g.label == 'Долги' && (debtWe != null || debtCo != null);
                  return _GridTile(
                    card: g,
                    onTap: () => _go(g.to),
                    debtWe: isDebts ? debtWe : null,
                    debtCo: isDebts ? debtCo : null,
                    dark: dark,
                    cs: cs,
                  );
                },
              ),
              if (_loadingDebts) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text('Обновляем долги…', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _pathToSection(String path) {
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

class _ActionCard {
  const _ActionCard(this.to, this.label, this.icon, this.color);
  final String to;
  final String label;
  final IconData icon;
  final Color color;
}

class _GridCard {
  const _GridCard(this.to, this.label, this.icon, this.color);
  final String to;
  final String label;
  final IconData icon;
  final Color color;
}

class _RatePill extends StatelessWidget {
  const _RatePill({required this.loading, required this.value, required this.onTap});
  final bool loading;
  final double? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = cs.outlineVariant.withValues(alpha: dark ? 0.4 : 0.55);

    return InkWell(
      borderRadius: AppShape.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: AppShape.brLg,
          border: Border.all(color: border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [cs.surfaceContainer.withValues(alpha: 0.9), cs.surfaceContainerLow.withValues(alpha: 0.95)]
                : [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.65)],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: dark ? 0.08 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: AppShape.br,
                    gradient: LinearGradient(
                      colors: [cs.primary.withValues(alpha: 0.85), cs.tertiary.withValues(alpha: 0.75)],
                    ),
                    boxShadow: [
                      BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text('\$', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onPrimary)),
                ),
                const SizedBox(width: 10),
                Text('Курс:', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
              ],
            ),
            Row(
              children: [
                Text(
                  loading ? '—' : (value != null ? '1 USD = ${value!.toStringAsFixed(2)} TJS' : '—'),
                  style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.75)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.card, required this.onTap});
  final _ActionCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: AppShape.brLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: AppShape.brLg,
            color: dark ? cs.surfaceContainer : cs.surface,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.22 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [card.color, card.color.withValues(alpha: 0.82)],
                  ),
                  borderRadius: AppShape.br,
                  boxShadow: [BoxShadow(color: card.color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Icon(card.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 18),
              Text(card.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.card,
    required this.onTap,
    required this.debtWe,
    required this.debtCo,
    required this.dark,
    required this.cs,
  });

  final _GridCard card;
  final VoidCallback onTap;
  final String? debtWe;
  final String? debtCo;
  final bool dark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.2 : 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    );

    return InkWell(
      borderRadius: AppShape.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: AppShape.brLg,
          color: dark ? cs.surfaceContainer : cs.surface,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.5)),
          boxShadow: [shadow],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppShape.br,
                        gradient: LinearGradient(
                          colors: [card.color.withValues(alpha: 0.12), card.color.withValues(alpha: 0.04)],
                        ),
                        border: Border.all(color: card.color.withValues(alpha: 0.55), width: 1.5),
                      ),
                      child: Center(
                        child: Icon(card.icon, size: 28, color: card.color),
                      ),
                    ),
                  ),
                  if (debtWe != null || debtCo != null)
                    Positioned(
                      top: 3,
                      left: 4,
                      right: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (debtWe != null)
                            Text(
                              debtWe!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: dark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48),
                                height: 1.1,
                              ),
                            ),
                          if (debtCo != null)
                            Text(
                              debtCo!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: dark ? const Color(0xFF86EFAC) : const Color(0xFF059669),
                                height: 1.1,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              card.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.1),
            ),
          ],
        ),
      ),
    );
  }
}
