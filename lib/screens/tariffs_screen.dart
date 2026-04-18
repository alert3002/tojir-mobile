import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

Map<String, dynamic> _tryJsonMap(String body) {
  try {
    final j = jsonDecode(body.isEmpty ? '{}' : body);
    return j is Map<String, dynamic> ? j : {};
  } catch (_) {
    return {};
  }
}

String _fmtDateOnly(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString();
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}

class TariffsScreen extends StatefulWidget {
  const TariffsScreen({super.key});

  @override
  State<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends State<TariffsScreen> {
  final ScrollController scrollCtrl = ScrollController();

  List<Map<String, dynamic>> tariffs = const [];
  Map<String, dynamic>? subscription;
  int? buyingId;

  int vipProducts = 2000;
  int vipStores = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (!mounted) return;
      await context.read<SessionController>().bootstrap();
    });
  }

  @override
  void dispose() {
    scrollCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('tariffs/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        setState(() => tariffs = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      } else {
        setState(() => tariffs = const []);
      }
    } catch (_) {
      if (mounted) setState(() => tariffs = const []);
    }

    try {
      final res = await api.get('tariffs/my/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = _tryJsonMap(res.body);
        final active = j['active'];
        setState(() => subscription = active == false ? null : j);
      } else {
        setState(() => subscription = null);
      }
    } catch (_) {
      if (mounted) setState(() => subscription = null);
    }
  }

  String _tariffKind(Map<String, dynamic> t) {
    final name = (t['name'] ?? '').toString().toLowerCase();
    if (name.contains('стандарт')) return 'standard';
    if (name.contains('vip')) return 'vip';
    if (name.contains('проб')) return 'trial';
    return 'other';
  }

  List<Map<String, dynamic>> get _sortedTariffs {
    final rank = <String, int>{'trial': 0, 'standard': 1, 'vip': 2, 'other': 3};
    final list = [...tariffs];
    list.sort((a, b) {
      final ra = rank[_tariffKind(a)] ?? 9;
      final rb = rank[_tariffKind(b)] ?? 9;
      if (ra != rb) return ra - rb;
      final pa = _asDouble(a['price_somoni']) ?? 0;
      final pb = _asDouble(b['price_somoni']) ?? 0;
      return pa.compareTo(pb);
    });
    return list;
  }

  ({double total, int baseProducts, int baseStores, int p, int s, int extraStores, int extraBlocks}) _calcVipPrice(
    Map<String, dynamic> t,
    int products,
    int stores,
  ) {
    final basePrice = _asDouble(t['price_somoni']) ?? 0;
    final baseProducts = _asInt(t['max_products']) ?? 2000;
    final baseStores = _asInt(t['max_stores']) ?? 5;
    final p = products < baseProducts ? baseProducts : products;
    final s = stores < baseStores ? baseStores : stores;
    final extraStores = (s - baseStores) > 0 ? (s - baseStores) : 0;
    final extraBlocks = (((p - baseProducts) > 0 ? (p - baseProducts) : 0) / 1000).ceil();
    final total = basePrice + (extraStores + extraBlocks) * 50.0;
    return (
      total: total,
      baseProducts: baseProducts,
      baseStores: baseStores,
      p: p,
      s: s,
      extraStores: extraStores,
      extraBlocks: extraBlocks,
    );
  }

  DateTime? _expiresAt(Map<String, dynamic>? user) {
    final raw = subscription?['expires_at'] ?? user?['subscription_expires_at'];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  int? _daysLeft(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final ms = expiresAt.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
    return (ms / 86400000).floor();
  }

  Future<void> _buyTariff(int tariffId, {Map<String, dynamic>? payload}) async {
    setState(() => buyingId = tariffId);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'tariffs/subscribe/',
        body: {'tariff_id': tariffId, ...(payload ?? const {})},
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        final detail = (data['detail'] ?? 'Не удалось активировать тариф').toString();
        if (detail.toLowerCase().contains('недостаточно средств')) {
          final missing = _asDouble(data['missing_amount']);
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Недостаточно средств'),
              content: Text(missing != null && missing > 0 ? '$detail\n\nНе хватает: ${missing.toStringAsFixed(2)} TJS' : detail),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).pushNamed('/profile');
                  },
                  child: const Text('Пополнить баланс'),
                ),
              ],
            ),
          );
          return;
        }
        throw Exception(detail);
      }

      _snack('Тариф активирован');
      setState(() => subscription = data['subscription'] is Map ? Map<String, dynamic>.from(data['subscription'] as Map) : subscription);
      await context.read<SessionController>().bootstrap();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => buyingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'tariffs', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final expiresAt = _expiresAt(u);
    final daysLeft = _daysLeft(expiresAt);
    final locked = u['subscription_is_expired'] == true;
    final canBuy = (u['role'] as String?) == 'businessman';

    final currentName = (subscription?['tariff_name'] ?? u['subscription_tariff_name'] ?? 'Нет активной подписки').toString();
    final expLabel = expiresAt != null ? 'Истекает: ${_fmtDateOnly(expiresAt.toIso8601String())}' : 'Срок не задан';

    final percent = expiresAt == null
        ? 0
        : (daysLeft == null)
            ? 0
            : (daysLeft <= 0 ? 0 : ((daysLeft / 30.0) * 100).clamp(0, 100).round());

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _load();
            if (!context.mounted) return;
            await context.read<SessionController>().bootstrap();
          },
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Тарифы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                        const SizedBox(height: 2),
                        Text('Управляйте подпиской и доступом сотрудников', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      scrollCtrl.animateTo(
                        scrollCtrl.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                      );
                    },
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Выбрать'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      shape: AppShape.roundedRect,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (locked)
                        _alertBox(
                          cs,
                          title: 'Подписка истекла',
                          text: 'Доступ к складу и работе продавцов временно ограничен. Продлите тариф, чтобы всё снова работало.',
                          kind: 'error',
                        )
                      else if (daysLeft != null && daysLeft <= 3)
                        _alertBox(
                          cs,
                          title: 'Подписка скоро закончится',
                          text: 'Осталось дней: ${daysLeft < 0 ? 0 : daysLeft}. Продлите заранее, чтобы не остановилась работа.',
                          kind: 'warning',
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.workspace_premium_outlined, color: cs.primary),
                                    const SizedBox(width: 6),
                                    const Text('Текущая подписка', style: TextStyle(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(currentName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(expLabel, style: TextStyle(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Center(
                              child: Text(
                                daysLeft == null ? '—' : '${daysLeft < 0 ? 0 : daysLeft}д',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: percent / 100.0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Доступные тарифы', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (_sortedTariffs.isEmpty)
                        Text('Нет тарифов.', style: TextStyle(color: cs.onSurfaceVariant))
                      else
                        ..._sortedTariffs.map((t) {
                          final kind = _tariffKind(t);
                          final id = _asInt(t['id']) ?? -1;
                          final basePrice = _asDouble(t['price_somoni']) ?? 0;
                          final duration = _asInt(t['duration_days']) ?? 0;
                          final maxProducts = t['max_products'];
                          final maxStores = _asInt(t['max_stores']) ?? 0;

                          final vipCalc = kind == 'vip' ? _calcVipPrice(t, vipProducts, vipStores) : null;
                          final priceText = kind == 'vip'
                              ? '${vipCalc!.total.toStringAsFixed(2)} смн'
                              : '${basePrice.toStringAsFixed(2)} смн';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              borderRadius: AppShape.br,
                              border: Border.all(color: kind == 'standard' ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (kind == 'standard')
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          color: cs.primaryContainer,
                                        ),
                                        child: Text('Рекомендация', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 12)),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (t['name'] ?? 'Тариф').toString(),
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          color: cs.primary.withValues(alpha: 0.12),
                                        ),
                                        child: Text(priceText, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _pill('$duration дней', cs),
                                      _pill('до ${maxProducts ?? '∞'} товаров', cs, icon: Icons.inventory_2_outlined),
                                      _pill('$maxStores магазинов', cs, icon: Icons.storefront_outlined),
                                    ],
                                  ),
                                  if (kind == 'vip') ...[
                                    const SizedBox(height: 12),
                                    Divider(color: cs.outlineVariant),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Expanded(child: Text('Магазины', style: TextStyle(fontWeight: FontWeight.w700))),
                                        SizedBox(
                                          width: 110,
                                          child: TextFormField(
                                            initialValue: vipStores.toString(),
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                            onChanged: (v) {
                                              final n = int.tryParse(v.replaceAll(RegExp(r'\\D'), ''));
                                              final min = vipCalc!.baseStores;
                                              setState(() => vipStores = (n == null || n < min) ? min : n);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Expanded(child: Text('Товары', style: TextStyle(fontWeight: FontWeight.w700))),
                                        SizedBox(
                                          width: 110,
                                          child: TextFormField(
                                            initialValue: vipProducts.toString(),
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                            onChanged: (v) {
                                              final n = int.tryParse(v.replaceAll(RegExp(r'\\D'), ''));
                                              final min = vipCalc!.baseProducts;
                                              setState(() => vipProducts = (n == null || n < min) ? min : n);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '+50 сомонӣ за каждый доп. магазин и за каждые доп. 1000 товаров',
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: (!canBuy || buyingId == id)
                                        ? null
                                        : () {
                                            if (id <= 0) return;
                                            if (kind == 'vip') {
                                              final calc = _calcVipPrice(t, vipProducts, vipStores);
                                              _buyTariff(
                                                id,
                                                payload: {
                                                  'custom_max_products': calc.p,
                                                  'custom_max_stores': calc.s,
                                                },
                                              );
                                              return;
                                            }
                                            _buyTariff(id);
                                          },
                                    child: buyingId == id
                                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Активировать'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, ColorScheme cs, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _alertBox(ColorScheme cs, {required String title, required String text, required String kind}) {
    final bg = kind == 'error' ? cs.errorContainer : cs.tertiaryContainer;
    final on = kind == 'error' ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: AppShape.br, color: bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: on)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: on.withValues(alpha: 0.95))),
        ],
      ),
    );
  }
}

