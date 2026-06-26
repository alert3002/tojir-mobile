import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../services/iap_service.dart';
import '../utils/permissions.dart';
import '../utils/platform_info.dart';
import '../widgets/app_scaffold.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const _cardBg = Color(0xFF1E293B);
const _blue = Color(0xFF2563EB);
const _priceGreen = Color(0xFF4ADE80);
const _priceGreenBg = Color(0xFF14532D);
const _badgeYellow = Color(0xFFFACC15);

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

String _fmtDateRu(DateTime? d) {
  if (d == null) return '—';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

class TariffsScreen extends StatefulWidget {
  const TariffsScreen({super.key});

  @override
  State<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends State<TariffsScreen> {
  final ScrollController scrollCtrl = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  List<Map<String, dynamic>> tariffs = const [];
  Map<String, dynamic>? subscription;
  int? buyingId;

  int vipProducts = 2000;
  int vipStores = 5;
  Map<String, ProductDetails> iapProducts = const {};

  String? _appleProductId(Map<String, dynamic> t) {
    final id = (t['apple_product_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  bool _isPaidTariff(Map<String, dynamic> t) => (_asDouble(t['price_somoni']) ?? 0) > 0;

  String _buyButtonLabel(Map<String, dynamic> t, bool activeNow) {
    if (activeNow) return 'Активен';
    if (!isIosApp) return 'Активировать';
    if (!_isPaidTariff(t)) return 'Активировать';
    final productId = _appleProductId(t);
    if (productId == null) return 'Скоро в App Store';
    final product = iapProducts[productId];
    return product?.price ?? 'App Store';
  }

  bool _buyButtonEnabled(Map<String, dynamic> t, bool canBuy, bool activeNow, int id) {
    if (!canBuy || activeNow || buyingId == id) return false;
    if (isIosApp && _isPaidTariff(t) && _appleProductId(t) == null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (!mounted) return;
      if (isIosApp) {
        await _loadIapProducts();
      }
      if (!mounted) return;
      await context.read<SessionController>().bootstrap();
    });
  }

  Future<void> _loadIapProducts() async {
    try {
      final ids = await IapService.instance.productIdsFromApi();
      if (ids.isEmpty || !mounted) return;
      final products = await IapService.instance.loadProducts(ids);
      if (mounted) setState(() => iapProducts = products);
    } catch (e) {
      if (mounted) _snack('App Store: $e', warning: true);
    }
  }

  @override
  void dispose() {
    scrollCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : warning
                ? Colors.orange.shade800
                : null,
      ),
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

  int _tariffRank(Map<String, dynamic> t) {
    final k = _tariffKind(t);
    if (k == 'vip') return 2;
    if (k == 'standard') return 1;
    if (k == 'trial') return 0;
    return 1;
  }

  String _currentKind(Map<String, dynamic>? user) {
    final name = (subscription?['tariff_name'] ?? user?['subscription_tariff_name'] ?? '').toString().toLowerCase();
    if (name.contains('vip')) return 'vip';
    if (name.contains('стандарт')) return 'standard';
    if (name.contains('проб')) return 'trial';
    return 'other';
  }

  bool _hasActiveSubscription(Map<String, dynamic>? user, bool locked, int? daysLeft) {
    if (locked) return false;
    if (subscription?['tariff'] == null && (user?['subscription_tariff_name'] ?? '').toString().isEmpty) return false;
    if (daysLeft != null && daysLeft < 0) return false;
    return true;
  }

  bool _isSameTariff(Map<String, dynamic> t, Map<String, dynamic>? user, bool hasActive) {
    if (!hasActive) return false;
    final tid = _asInt(subscription?['tariff']);
    final id = _asInt(t['id']);
    if (tid != null && id != null && tid == id) return true;
    return _tariffKind(t) == _currentKind(user) && _currentKind(user) != 'other';
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

  List<Map<String, dynamic>> _visibleTariffs(Map<String, dynamic>? user, bool hasActive) {
    final sorted = _sortedTariffs;
    if (!hasActive) return sorted;
    final kind = _currentKind(user);
    final floor = kind == 'vip'
        ? 2
        : kind == 'standard'
            ? 1
            : kind == 'trial'
                ? 0
                : 0;
    return sorted.where((t) => _tariffRank(t) >= floor).toList();
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

  double _getTariffPrice(Map<String, dynamic> t) {
    if (_tariffKind(t) == 'vip') return _calcVipPrice(t, vipProducts, vipStores).total;
    return _asDouble(t['price_somoni']) ?? 0;
  }

  DateTime? _expiresAt(Map<String, dynamic>? user) {
    final raw = subscription?['expires_at'] ?? user?['subscription_expires_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  int? _daysLeft(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final ms = expiresAt.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
    return (ms / 86400000).floor();
  }

  void _scrollToTariffs() {
    final ctx = _listKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      return;
    }
    scrollCtrl.animateTo(
      scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  Future<void> _requestActivateTariff(Map<String, dynamic> t, Map<String, dynamic>? user, bool hasActive, {Map<String, dynamic>? payload}) async {
    final canBuy = (user?['role'] as String?) == 'businessman';
    if (!canBuy) return;

    if (_isSameTariff(t, user, hasActive)) {
      _snack('Этот тариф уже активен', warning: true);
      return;
    }

    final id = _asInt(t['id']);
    if (id == null) return;

    final price = _getTariffPrice(t);
    final priceLabel = '${price.toStringAsFixed(2)} смн';
    final currentName = (subscription?['tariff_name'] ?? user?['subscription_tariff_name'] ?? '').toString();
    final daysLeft = _daysLeft(_expiresAt(user));

    if (hasActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Подтвердите активацию тарифа'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Сейчас: $currentName${daysLeft != null ? ' (осталось ${daysLeft < 0 ? 0 : daysLeft} дн.)' : ''}'),
                const SizedBox(height: 8),
                Text('Новый тариф: ${t['name']} — ${t['duration_days']} дн.'),
                const SizedBox(height: 8),
                Text('Лимиты: до ${t['max_products'] ?? '∞'} товаров, ${t['max_stores']} магазин(ов).'),
                const SizedBox(height: 8),
                Text(
                  isIosApp && _isPaidTariff(t)
                      ? 'Оплата через App Store (Apple).'
                      : isIosApp
                          ? 'Бесплатная активация на сервере Tojir.'
                          : 'Срок подписки продлится на ${t['duration_days']} дней от текущей даты окончания.',
                ),
                if (!isIosApp) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _priceGreen.withValues(alpha: 0.35)),
                      color: _priceGreen.withValues(alpha: 0.08),
                    ),
                    child: Text('С баланса спишется: $priceLabel', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isIosApp && _isPaidTariff(t) ? 'Купить в App Store' : 'Активировать'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    if (isIosApp && _isPaidTariff(t)) {
      final productId = _appleProductId(t);
      if (productId != null) {
        await _buyTariffViaApple(t, productId, payload: payload);
        return;
      }
      _snack(
        'Укажите Apple product ID в админке для «${t['name']}» '
        '(напр. tj.tojir.tariff.standard.monthly).',
        error: true,
      );
      return;
    }

    await _buyTariff(id, payload: payload);
  }

  Future<void> _buyTariffViaApple(
    Map<String, dynamic> t,
    String productId, {
    Map<String, dynamic>? payload,
  }) async {
    final id = _asInt(t['id']);
    if (id == null) return;
    final product = iapProducts[productId];
    if (product == null) {
      _snack('Продукт не найден в App Store. Проверьте App Store Connect.', error: true);
      return;
    }

    setState(() => buyingId = id);
    await IapService.instance.purchaseSubscription(
      product: product,
      tariffId: id,
      onSuccess: () async {
        if (!mounted) return;
        _snack('Подписка активирована');
        await _load();
        if (!mounted) return;
        await context.read<SessionController>().bootstrap();
        if (mounted) setState(() => buyingId = null);
      },
      onError: (msg) {
        if (mounted) {
          _snack(msg, error: true);
          setState(() => buyingId = null);
        }
      },
    );
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
        final code = data['code']?.toString();
        if (code == 'tariff_already_active' || code == 'tariff_downgrade') {
          _snack(detail, warning: true);
          return;
        }
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
                  child: Text(isIosApp ? 'Как пополнить' : 'Пополнить баланс'),
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

  Widget _alertBox({required String title, required String text, required Color bg, required Color border, required Color fg}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: bg,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.9), height: 1.35)),
        ],
      ),
    );
  }

  Widget _currentSubscriptionCard(Map<String, dynamic>? user, bool locked, int? daysLeft, DateTime? expiresAt) {
    final currentName = (subscription?['tariff_name'] ?? user?['subscription_tariff_name'] ?? 'Нет активной подписки').toString();
    final percent = expiresAt == null ? 0.0 : ((daysLeft == null ? 0 : (daysLeft < 0 ? 0 : daysLeft)) / 30.0 * 100).clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (locked)
            _alertBox(
              title: 'Подписка истекла',
              text: 'Доступ к складу и работе продавцов временно ограничен. Продлите тариф, чтобы всё снова работало.',
              bg: const Color(0xFF7F1D1D).withValues(alpha: 0.25),
              border: const Color(0xFFEF4444).withValues(alpha: 0.4),
              fg: const Color(0xFFFECACA),
            )
          else if (daysLeft != null && daysLeft <= 3)
            _alertBox(
              title: 'Подписка скоро закончится',
              text: 'Осталось дней: ${daysLeft < 0 ? 0 : daysLeft}. Продлите заранее, чтобы не остановилась работа.',
              bg: const Color(0xFF78350F).withValues(alpha: 0.25),
              border: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              fg: const Color(0xFFFDE68A),
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
                        Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.white.withValues(alpha: 0.65)),
                        const SizedBox(width: 6),
                        Text('Текущая подписка', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(currentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: Colors.white.withValues(alpha: 0.55)),
                        const SizedBox(width: 6),
                        Text(
                          expiresAt != null ? 'Истекает: ${_fmtDateRu(expiresAt)}' : 'Срок не задан',
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percent / 100,
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      color: _blue,
                    ),
                    Text(
                      daysLeft == null ? '—' : '${daysLeft < 0 ? 0 : daysLeft}д',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tariffCard(
    Map<String, dynamic> t,
    Map<String, dynamic>? user,
    bool canBuy,
    bool hasActive,
  ) {
    final kind = _tariffKind(t);
    final id = _asInt(t['id']) ?? -1;
    final activeNow = _isSameTariff(t, user, hasActive);
    final vipCalc = kind == 'vip' ? _calcVipPrice(t, vipProducts, vipStores) : null;
    final priceText = kind == 'vip'
        ? '${vipCalc!.total.toStringAsFixed(2)} смн'
        : '${(_asDouble(t['price_somoni']) ?? 0).toStringAsFixed(2)} смн';
    final duration = _asInt(t['duration_days']) ?? 0;
    final maxProducts = t['max_products'];
    final maxStores = _asInt(t['max_stores']) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: kind == 'standard' ? const Color(0xFF3B82F6).withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: kind == 'standard'
            ? [BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 10))]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kind == 'standard')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _badgeYellow.withValues(alpha: 0.5)),
                      color: _badgeYellow.withValues(alpha: 0.12),
                    ),
                    child: const Text('Рекомендация', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _badgeYellow)),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, size: 18, color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (t['name'] ?? 'Тариф').toString(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _priceGreenBg.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _priceGreen.withValues(alpha: 0.35)),
                  ),
                  child: Text(priceText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _priceGreen)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text('$duration дней', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                ),
                Text(
                  'до ${maxProducts ?? '∞'} товаров · $maxStores магазинов',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
            if (kind == 'vip' && !isIosApp) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
              const SizedBox(height: 12),
              _vipNumberRow(
                label: 'Магазины',
                value: vipStores,
                min: vipCalc!.baseStores,
                step: 1,
                onChanged: (v) => setState(() => vipStores = v),
              ),
              const SizedBox(height: 8),
              _vipNumberRow(
                label: 'Товары',
                value: vipProducts,
                min: vipCalc.baseProducts,
                step: 1000,
                onChanged: (v) => setState(() => vipProducts = v),
              ),
              const SizedBox(height: 8),
              Text(
                '+50 сомонӣ за каждый доп. магазин и за каждые доп. 1000 товаров',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), height: 1.35),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _buyButtonEnabled(t, canBuy, activeNow, id)
                  ? () {
                      if (isIosApp && _tariffKind(t) == 'vip') {
                        _snack('VIP в App Store скоро. Пока доступен тариф «Стандарт».', warning: true);
                        return;
                      }
                      if (isIosApp) {
                        _requestActivateTariff(t, user, hasActive);
                        return;
                      }
                      if (_tariffKind(t) == 'vip') {
                        final calc = _calcVipPrice(t, vipProducts, vipStores);
                        _requestActivateTariff(
                          t,
                          user,
                          hasActive,
                          payload: {'custom_max_products': calc.p, 'custom_max_stores': calc.s},
                        );
                        return;
                      }
                      _requestActivateTariff(t, user, hasActive);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: activeNow ? const Color(0xFF3A4558) : _blue,
                disabledBackgroundColor: const Color(0xFF3A4558),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
                minimumSize: const Size(double.infinity, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: buyingId == id
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_buyButtonLabel(t, activeNow)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vipNumberRow({
    required String label,
    required int value,
    required int min,
    required int step,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        SizedBox(
          width: 110,
          child: TextFormField(
            key: ValueKey('$label-$value'),
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
            ),
            onChanged: (v) {
              final n = int.tryParse(v.replaceAll(RegExp(r'\D'), ''));
              if (n == null) return;
              onChanged(n < min ? min : n);
            },
          ),
        ),
        const SizedBox(width: 4),
        Column(
          children: [
            InkWell(
              onTap: () => onChanged(value + step),
              child: Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: Colors.white.withValues(alpha: 0.6)),
            ),
            InkWell(
              onTap: () => onChanged(value - step < min ? min : value - step),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ],
    );
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
    final hasActive = _hasActiveSubscription(u, locked, daysLeft);
    final visible = _visibleTariffs(u, hasActive);

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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Text('Тарифы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text(
                'Управляйте подпиской и доступом сотрудников',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scrollToTariffs,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Выбрать тариф'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _currentSubscriptionCard(u, locked, daysLeft, expiresAt),
              Container(
                key: _listKey,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Доступные тарифы', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    if (hasActive && visible.isEmpty)
                      _alertBox(
                        title: 'Тарифы ниже текущего скрыты',
                        text: 'После окончания подписки снова появятся все варианты. Сейчас можно выбрать только тариф не ниже текущего.',
                        bg: _blue.withValues(alpha: 0.12),
                        border: _blue.withValues(alpha: 0.3),
                        fg: const Color(0xFFBFDBFE),
                      )
                    else if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Нет доступных тарифов', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    else
                      for (final t in visible) _tariffCard(t, u, canBuy, hasActive),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
