import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/home_cards.dart';
import '../utils/json_parse.dart';
import '../utils/number_format.dart';
import '../utils/permissions.dart';
import '../widgets/ai_assistant_fab.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/businessman_home_grid.dart';
import 'platform_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double? _usdToTjs;
  List<Map<String, dynamic>> _weOwe = const [];
  List<Map<String, dynamic>> _clientOwes = const [];
  Map<String, dynamic>? _kpi;
  bool _becomeLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  Future<void> _loadAll() async {
    await Future.wait([_loadRate(), _loadDebtTotals(), _loadKpi()]);
  }

  Future<void> _loadKpi() async {
    final u = _user;
    if (u == null || !isBusinessmanHome(u)) return;
    if (u['warehouse'] == null) return;
    try {
      final res = await context.read<ApiClient>().get('inventory/dashboard/snapshot/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic> && d['has_warehouse'] == true) {
          setState(() => _kpi = d);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRate() async {
    final u = _user;
    if (u == null || !canAccessSection(u, 'course', null)) return;
    try {
      final res = await context.read<ApiClient>().get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final v = d['usd_to_tjs'];
        final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        setState(() => _usdToTjs = (n != null && n > 0) ? n : null);
      }
    } catch (_) {}
  }

  Future<void> _loadDebtTotals() async {
    final u = _user;
    if (u == null || isClientLike(u)) return;
    if (!canAccessSection(u, 'debts', null)) return;
    try {
      final res = await context.read<ApiClient>().get('inventory/debts/totals-badge/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _weOwe = (d['we_owe'] is List) ? (d['we_owe'] as List).cast<Map<String, dynamic>>() : const [];
          _clientOwes = (d['client_owes'] is List) ? (d['client_owes'] as List).cast<Map<String, dynamic>>() : const [];
        });
      }
    } catch (_) {}
  }

  void _go(String route) {
    if (route == '/') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _becomeBusinessman() async {
    setState(() => _becomeLoading = true);
    try {
      await context.read<SessionController>().becomeBusinessman();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы бизнесмен. Создайте склад в профиле.')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/profile', (r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _becomeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user ?? const <String, dynamic>{};
    final role = u['role'] as String?;
    if (role == 'platform' || (role == 'moderator' && (u['moderator_scope'] as String?) == 'platform')) {
      return const PlatformHomeRedirect();
    }
    final debtWe = formatDebtBadgeAmounts(_weOwe, true);
    final debtCo = formatDebtBadgeAmounts(_clientOwes, false);
    final canSeeCourse = canAccessSection(u, 'course', null);

    if (isClientLike(u)) {
      return AppScaffold(
        child: _ClientHome(
          user: u,
          onNavigate: _go,
          onBecomeBusinessman: _becomeBusinessman,
          onRefresh: _loadAll,
          loading: _becomeLoading,
        ),
      );
    }

    if (role == 'seller') {
      return AppScaffold(
        child: _SellerHome(
          user: u,
          usdToTjs: _usdToTjs,
          canSeeCourse: canSeeCourse,
          debtWe: debtWe,
          debtCo: debtCo,
          onNavigate: _go,
          onRefresh: _loadAll,
        ),
      );
    }

    final businessman = isBusinessmanHome(u);
    final gridCards = businessman
        ? getBusinessmanGridCards(u)
        : (role == 'nasiya' ? getNasiyaGridCards(u) : getDefaultGridCards(u));

    return AppScaffold(
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: EdgeInsets.fromLTRB(12, 6, 12, businessman ? 88 : 12),
              children: [
                if (businessman && _kpi != null) _KpiStrip(kpi: _kpi!),
                if (canSeeCourse) ...[
                  _RatePill(value: _usdToTjs, onTap: () => _go('/course')),
                  SizedBox(height: businessman ? 10 : 8),
                ],
                if (gridCards.isNotEmpty)
                  businessman
                      ? BusinessmanHomeGrid(
                          cards: gridCards,
                          debtWe: debtWe,
                          debtCo: debtCo,
                          onTap: _go,
                        )
                      : _AccentGrid(
                          cards: gridCards,
                          columns: 2,
                          debtWe: debtWe,
                          debtCo: debtCo,
                          onTap: _go,
                        ),
              ],
            ),
          ),
          if (businessman)
            const Positioned(
              right: 12,
              bottom: 8,
              child: AiAssistantFab(),
            ),
        ],
      ),
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.kpi});
  final Map<String, dynamic> kpi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final today = kpi['today'];
    var salesTjs = '0';
    if (today is Map) {
      final rows = today['cashflow_by_currency'] ?? today['cashflow_summary'];
      if (rows is List) {
        for (final row in rows) {
          if (row is Map && (row['currency']?.toString().toUpperCase() ?? '') == 'TJS') {
            salesTjs = row['sales']?.toString() ?? '0';
            break;
          }
        }
      }
    }
    final expenses = parseJsonDouble(kpi['expenses_today']) ?? 0;
    final lowStock = parseJsonInt(kpi['low_stock_count']) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)),
      ),
      child: Row(
        children: [
          _KpiItem(label: 'Продажи сегодня', value: '${formatRuInt(num.tryParse(salesTjs.replaceAll(' ', '')) ?? 0)} TJS'),
          _KpiItem(label: 'Расходы', value: '${expenses.round()} TJS'),
          _KpiItem(label: 'Мало на складе', value: '$lowStock'),
        ],
      ),
    );
  }

}

class _KpiItem extends StatelessWidget {
  const _KpiItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _RatePill extends StatelessWidget {
  const _RatePill({required this.value, required this.onTap});
  final double? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFF2563EB).withValues(alpha: 0.22),
            ),
            color: cs.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF2563EB).withValues(alpha: 0.22),
                      const Color(0xFF22C55E).withValues(alpha: 0.18),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: dark ? 0.18 : 0.14),
                      blurRadius: dark ? 26 : 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Text(
                  '\$',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: dark ? const Color(0xFFF1F5F9).withValues(alpha: 0.95) : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('Курс:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurfaceVariant)),
              const Spacer(),
              Flexible(
                child: Text(
                  value != null ? '1 USD = ${formatRuMoney(value!, fractionDigits: 2)} TJS' : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentGrid extends StatelessWidget {
  const _AccentGrid({
    required this.cards,
    required this.columns,
    required this.debtWe,
    required this.debtCo,
    required this.onTap,
  });

  final List<HomeCard> cards;
  final int columns;
  final String? debtWe;
  final String? debtCo;
  final void Function(String route) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF151D2E) : cs.surface;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: columns == 3 ? 0.88 : 1.02,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        final isDebts = card.route == '/debts' && card.label == 'Долги';
        final accent = card.color;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(card.route),
            child: Ink(
              padding: EdgeInsets.fromLTRB(5, columns == 3 ? 10 : 12, 5, columns == 3 ? 8 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withValues(alpha: 0.14), cardBg],
                  stops: const [0.0, 0.72],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isDebts && (debtWe != null || debtCo != null))
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                if (debtWe != null)
                                  Text(
                                    debtWe!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFE11D48)),
                                  ),
                                if (debtCo != null)
                                  Text(
                                    debtCo!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                  ),
                              ],
                            ),
                          ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            color: accent.withValues(alpha: 0.14),
                            border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
                            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
                          ),
                          child: Icon(card.icon, size: 20, color: accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: columns == 3 ? 11 : 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClientHome extends StatelessWidget {
  const _ClientHome({
    required this.user,
    required this.onNavigate,
    required this.onBecomeBusinessman,
    required this.onRefresh,
    required this.loading,
  });

  final Map<String, dynamic> user;
  final void Function(String route) onNavigate;
  final VoidCallback onBecomeBusinessman;
  final Future<void> Function() onRefresh;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cards = getClientHomeCards(user);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          _WelcomeHeader(
            name: _clientName(user),
            outlet: null,
          ),
          const SizedBox(height: 10),
          if (cards.isNotEmpty)
            _SellerMenuGrid(
              cards: cards,
              debtCo: null,
              onTap: onNavigate,
            ),
          const SizedBox(height: 14),
          if ((user['role'] as String?) == 'client') _BecomeBusinessmanCard(onTap: onBecomeBusinessman, loading: loading),
        ],
      ),
    );
  }

  static String _clientName(Map<String, dynamic> user) {
    final fn = (user['first_name'] as String?)?.trim() ?? '';
    final ln = (user['last_name'] as String?)?.trim() ?? '';
    final full = '$fn $ln'.trim();
    if (full.isNotEmpty) return full;
    return (user['phone'] as String?) ?? 'Клиент';
  }
}

class _SellerHome extends StatelessWidget {
  const _SellerHome({
    required this.user,
    required this.usdToTjs,
    required this.canSeeCourse,
    required this.debtWe,
    required this.debtCo,
    required this.onNavigate,
    required this.onRefresh,
  });

  final Map<String, dynamic> user;
  final double? usdToTjs;
  final bool canSeeCourse;
  final String? debtWe;
  final String? debtCo;
  final void Function(String route) onNavigate;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final salesCard = getSellerSalesCard(user);
    final secondary = getSellerSecondaryCards(user);
    final outlet = sellerOutletText(user);
    final bottomPad = salesCard != null ? 100.0 : 12.0;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(12, 6, 12, bottomPad),
            children: [
              if (canSeeCourse) ...[
                _RatePill(value: usdToTjs, onTap: () => onNavigate('/course')),
                const SizedBox(height: 10),
              ],
              _WelcomeHeader(name: sellerDisplayName(user), outlet: outlet),
              const SizedBox(height: 10),
              if (secondary.isNotEmpty)
                _SellerMenuGrid(
                  cards: secondary,
                  debtCo: debtCo,
                  onTap: onNavigate,
                ),
            ],
          ),
        ),
        if (salesCard != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: _SellerHero(onTap: () => onNavigate('/sales')),
          ),
      ],
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name, this.outlet});
  final String name;
  final String? outlet;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerLow,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ЗДРАВСТВУЙТЕ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
                Text(name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface)),
                if (outlet != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.storefront_outlined, size: 14, color: cs.primary.withValues(alpha: 0.85)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          outlet!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF93C5FD)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerMenuGrid extends StatelessWidget {
  const _SellerMenuGrid({required this.cards, required this.debtCo, required this.onTap});
  final List<HomeCard> cards;
  final String? debtCo;
  final void Function(String route) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        final tone = sellerCardTone(card.route);
        final gradient = sellerToneGradient(tone);
        final hint = kSellerHints[card.route];
        final isDebts = card.route == '/debts' && card.label == 'Долги';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(card.route),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Icon(card.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(card.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                        if (hint != null || (isDebts && debtCo != null))
                          Text(
                            [
                              if (isDebts && debtCo != null) debtCo,
                              if (hint != null) hint,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.82)),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white.withValues(alpha: 0.85)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SellerHero extends StatelessWidget {
  const _SellerHero({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF22C55E), Color(0xFF16A34A), Color(0xFF15803D)],
              stops: [0.0, 0.55, 1.0],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.45), blurRadius: 32, offset: const Offset(0, 12))],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.attach_money_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Начать продажу', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    SizedBox(height: 3),
                    Text('Оформить чек и принять оплату', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BecomeBusinessmanCard extends StatelessWidget {
  const _BecomeBusinessmanCard({required this.onTap, required this.loading});
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: AppShape.brLg,
        color: cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront_outlined, size: 28, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Вести бизнес', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text(
                      'Склад, продажи, магазины и отчёты — после переключения роли на бизнесмена.',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: loading ? null : onTap,
            child: loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Стать бизнесменом'),
          ),
        ],
      ),
    );
  }
}

/// Как Home.jsx → Navigate to /platform для роли platform.
class PlatformHomeRedirect extends StatelessWidget {
  const PlatformHomeRedirect({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(child: PlatformDashboardScreen());
  }
}
