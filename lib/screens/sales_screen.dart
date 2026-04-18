import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/date_range_presets.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/quick_date_range_chips.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Map<String, dynamic>> outlets = const [];
  int? saleOutletId;
  DateTime saleDate = DateTime.now();

  double usdToTjs = 11.5;

  bool loadingOutlets = false;
  bool loadingProducts = false;
  bool loadingHistory = false;

  List<Map<String, dynamic>> outletProducts = const [];
  final Set<int> selectedProductIds = <int>{};
  final Map<int, _LineEdit> edits = <int, _LineEdit>{};

  // Checkout
  String paymentMethod = 'cash'; // cash|card|nasiya|partial
  String buyerName = '';
  String buyerPhone9 = '';
  String buyerComment = '';
  double cashPaidPartial = 0;

  String? checkoutVerificationId;
  bool smsVerified = false;
  bool sendingSms = false;
  bool verifyingSms = false;
  String smsCode = '';
  int smsCooldownSec = 0;
  Timer? _smsTimer;

  // History
  String historySearch = '';
  DateTimeRange? historyRange;
  String? historyDatePreset;
  int? filterOutletId;
  bool showTrash = false;
  List<Map<String, dynamic>> sales = const [];

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      await _loadOutlets();
      await _loadHistory();
    });
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    super.dispose();
  }

  void _startSmsCooldown60s() {
    _smsTimer?.cancel();
    setState(() => smsCooldownSec = 60);
    _smsTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        smsCooldownSec = (smsCooldownSec - 1).clamp(0, 60);
      });
      if (smsCooldownSec <= 0) t.cancel();
    });
  }

  Future<void> _loadRate() async {
    final u = _user;
    if (u == null) return;
    if (!canAccessSection(u, 'course', null)) return;
    try {
      final api = context.read<ApiClient>();
      final res = await api.get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final v = d['usd_to_tjs'];
        final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        if (n != null && n > 0) setState(() => usdToTjs = n);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadOutlets() async {
    final u = _user;
    if (u == null) return;
    setState(() => loadingOutlets = true);
    try {
      final api = context.read<ApiClient>();
      // Server decides allowed outlets for seller; for others warehouse may be applied server-side too.
      final res = await api.get('inventory/outlets');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = (d is List) ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => outlets = items);
        if (saleOutletId == null && items.isNotEmpty) {
          final first = items.first;
          final id = first['id'];
          final n = id is num ? id.toInt() : int.tryParse(id?.toString() ?? '');
          if (n != null) {
            setState(() {
              saleOutletId = n;
              if (u['role'] == 'seller' && items.length == 1) filterOutletId = n;
            });
            await _loadOutletProducts(n);
          }
        } else if (saleOutletId != null) {
          await _loadOutletProducts(saleOutletId!);
        }
      }
    } catch (_) {
      if (mounted) setState(() => outlets = const []);
    } finally {
      if (mounted) setState(() => loadingOutlets = false);
    }
  }

  Future<void> _loadOutletProducts(int outletId) async {
    setState(() => loadingProducts = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.get('inventory/outlets/$outletId/products/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = (d is List) ? d : <dynamic>[];
        final items = list.cast<Map<String, dynamic>>();
        setState(() {
          outletProducts = items;
        });
        // init edits for visible products
        for (final p in items) {
          final pid = _asInt(p['product_id']);
          if (pid == null) continue;
          edits.putIfAbsent(pid, () {
            final price = _asDouble(p['sale_price']) ?? 0;
            return _LineEdit(quantity: 1, unitPriceTjs: price, currency: 'TJS');
          });
        }
      } else {
        setState(() => outletProducts = const []);
      }
    } catch (_) {
      if (mounted) setState(() => outletProducts = const []);
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  double get cartTotalTjs {
    double sum = 0;
    for (final pid in selectedProductIds) {
      final e = edits[pid];
      if (e == null) continue;
      sum += e.quantity * e.unitPriceTjs;
    }
    return sum;
  }

  bool get needsContact => paymentMethod == 'nasiya' || paymentMethod == 'partial';

  bool get phoneOk => !needsContact || buyerPhone9.replaceAll(RegExp(r'\D'), '').length == 9;
  bool get commentOk => !needsContact || buyerComment.trim().isNotEmpty;
  bool get smsOk => !needsContact || smsVerified;

  bool get baseLinesOk {
    if (selectedProductIds.isEmpty) return false;
    for (final pid in selectedProductIds) {
      final p = outletProducts.firstWhere(
        (x) => _asInt(x['product_id']) == pid,
        orElse: () => const <String, dynamic>{},
      );
      if (p.isEmpty) return false;
      final inStore = _asDouble(p['quantity']) ?? 0;
      final costTjs = _asDouble(p['sale_price']) ?? 0;
      final e = edits[pid];
      if (e == null) return false;
      if (e.quantity <= 0) return false;
      if (e.quantity > inStore) return false;
      if (e.unitPriceTjs <= 0) return false;
      if (e.unitPriceTjs < costTjs) return false;
    }
    return true;
  }

  bool get partialOk {
    if (paymentMethod != 'partial') return true;
    final v = cashPaidPartial;
    if (v.isNaN || v.isInfinite) return false;
    if (v < 0) return false;
    if (v > cartTotalTjs) return false;
    return cartTotalTjs > 0;
  }

  bool get canSubmitCart => baseLinesOk && phoneOk && commentOk && smsOk && partialOk;

  Future<void> _requestCheckoutSms() async {
    if (!needsContact) return;
    final digits = buyerPhone9.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9) {
      _snack('Введите номер после +992 (9 цифр)', error: true);
      return;
    }
    if (buyerComment.trim().isEmpty) {
      _snack('Заполните комментарий для SMS', error: true);
      return;
    }
    if (cartTotalTjs <= 0) {
      _snack('Сначала добавьте товары в корзину', error: true);
      return;
    }

    setState(() => sendingSms = true);
    try {
      final api = context.read<ApiClient>();
      final label = selectedProductIds
          .map((pid) => outletProducts.firstWhere((p) => _asInt(p['product_id']) == pid, orElse: () => const {}))
          .map((p) => (p['product_name'] ?? p['name'] ?? 'Товар').toString())
          .join(', ');
      final res = await api.post(
        'inventory/sales/checkout-sms/request/',
        body: {
          'phone': '992$digits',
          'payment_method': paymentMethod,
          'total_tjs': cartTotalTjs,
          'cart_label': label.length > 400 ? label.substring(0, 400) : label,
          'comment': buyerComment.trim(),
        },
      );
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode != 200) {
        final msg = (data is Map && data['detail'] is String) ? data['detail'] as String : 'Не удалось отправить SMS';
        throw Exception(msg);
      }
      setState(() {
        checkoutVerificationId = (data is Map) ? data['verification_id']?.toString() : null;
        smsVerified = false;
        smsCode = '';
      });
      _startSmsCooldown60s();
      _snack((data is Map && data['sms_sent'] == true) ? 'SMS отправлено' : (data['warning']?.toString() ?? 'SMS не отправлено'));
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => sendingSms = false);
    }
  }

  Future<void> _verifyCheckoutSms() async {
    final vid = checkoutVerificationId;
    final c = smsCode.replaceAll(RegExp(r'\D'), '');
    if (vid == null || c.isEmpty) return;
    setState(() => verifyingSms = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/sales/checkout-sms/verify/',
        body: {'verification_id': vid, 'code': c},
      );
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode != 200) {
        final msg = (data is Map && data['detail'] is String) ? data['detail'] as String : 'Неверный код';
        throw Exception(msg);
      }
      setState(() => smsVerified = true);
      _snack('Код подтверждён — можно завершить продажу');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => verifyingSms = false);
    }
  }

  Future<void> _submitCart() async {
    final outletId = saleOutletId;
    if (outletId == null) {
      _snack('Выберите магазин', error: true);
      return;
    }
    if (!canSubmitCart) {
      _snack('Проверьте корзину, телефон, комментарий и SMS (если требуется)', error: true);
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final pid in selectedProductIds) {
      final e = edits[pid];
      if (e == null) continue;
      items.add({'product': pid, 'quantity': e.quantity, 'unit_price': e.unitPriceTjs, 'currency': 'TJS'});
    }
    final digits = buyerPhone9.replaceAll(RegExp(r'\D'), '');
    final body = <String, dynamic>{
      'outlet': outletId,
      'sold_at': _fmtYmd(saleDate),
      'payment_method': paymentMethod,
      'buyer_name': buyerName.trim(),
      'buyer_phone': digits.length == 9 ? '992$digits' : '',
      'buyer_comment': needsContact ? buyerComment.trim() : '',
      'items': items,
    };
    if (paymentMethod == 'partial') body['cash_paid_tjs'] = cashPaidPartial;
    if (paymentMethod == 'nasiya') body['cash_paid_tjs'] = null;
    if (needsContact && checkoutVerificationId != null) body['checkout_sms_verification_id'] = checkoutVerificationId;

    try {
      final api = context.read<ApiClient>();
      final res = await api.post('inventory/sales/batch/', body: body);
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = (data is Map)
            ? (data['detail'] ?? data['items'] ?? (data['checkout_sms_verification_id'] is List ? (data['checkout_sms_verification_id'] as List).first : null))
            : null;
        throw Exception(msg?.toString() ?? 'Ошибка');
      }
      _snack('Оформлено продаж: ${(data is Map && data['count'] != null) ? data['count'] : items.length}');
      setState(() {
        selectedProductIds.clear();
        buyerComment = '';
        smsVerified = false;
        checkoutVerificationId = null;
        smsCode = '';
        paymentMethod = 'cash';
        cashPaidPartial = 0;
      });
      await _loadHistory();
      await _loadOutletProducts(outletId);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _pickHistoryRange() async {
    final now = DateTime.now();
    final initial = historyRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: 'Период',
      cancelText: 'Отмена',
      confirmText: 'ОК',
    );
    if (picked == null || !mounted) return;
    setState(() {
      historyRange = picked;
      historyDatePreset = 'period';
    });
    await _loadHistory();
  }

  void _applyHistoryDateQuick(String kind) {
    if (kind == 'period') {
      _pickHistoryRange();
      return;
    }
    final r = DateRangePresets.rangeForPreset(kind);
    if (r == null) return;
    setState(() {
      historyDatePreset = kind;
      historyRange = r;
    });
    _loadHistory();
  }

  void _clearHistoryDateFilter() {
    setState(() {
      historyRange = null;
      historyDatePreset = null;
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => loadingHistory = true);
    try {
      final api = context.read<ApiClient>();
      final qp = <String, String>{};
      if (filterOutletId != null) qp['outlet'] = filterOutletId.toString();
      if (historySearch.trim().isNotEmpty) qp['search'] = historySearch.trim();
      if (historyRange != null) {
        qp['date_from'] = _fmtYmd(historyRange!.start);
        qp['date_to'] = _fmtYmd(historyRange!.end);
      }
      if (showTrash) qp['trash'] = '1';
      final path = qp.isEmpty ? 'inventory/sales/' : 'inventory/sales/?${Uri(queryParameters: qp).query}';
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = (d is List) ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => sales = items);
      } else {
        setState(() => sales = const []);
      }
    } catch (_) {
      if (mounted) setState(() => sales = const []);
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    final text = msg.replaceFirst('Exception: ', '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.isEmpty ? (error ? 'Ошибка' : 'Готово') : text),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  void _addProduct(int pid) {
    if (!outletProducts.any((p) => _asInt(p['product_id']) == pid)) return;
    setState(() {
      selectedProductIds.add(pid);
      edits.putIfAbsent(pid, () {
        final p = outletProducts.firstWhere((x) => _asInt(x['product_id']) == pid, orElse: () => const {});
        final price = _asDouble(p['sale_price']) ?? 0;
        return _LineEdit(quantity: 1, unitPriceTjs: price, currency: 'TJS');
      });
      // reset sms state when cart changes / payment changes like web
      smsVerified = false;
      checkoutVerificationId = null;
      smsCode = '';
      smsCooldownSec = 0;
      _smsTimer?.cancel();
    });
  }

  void _removeProduct(int pid) {
    setState(() {
      selectedProductIds.remove(pid);
      smsVerified = false;
      checkoutVerificationId = null;
      smsCode = '';
      smsCooldownSec = 0;
      _smsTimer?.cancel();
    });
  }

  Future<void> _openProductPicker() async {
    final outletId = saleOutletId;
    if (outletId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductPickerSheet(
        products: outletProducts,
        selectedIds: selectedProductIds,
        onPick: (pid) {
          Navigator.of(ctx).pop();
          _addProduct(pid);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'sales', null)) {
      return const AppScaffold(
        child: SafeArea(
          top: false,
          child: Center(child: Text('Нет доступа')),
        ),
      );
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadOutlets();
            await _loadHistory();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Text('Продажа', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              _Card(
                title: 'Оформить продажу',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _OutletDropdown(
                            outlets: outlets,
                            value: saleOutletId,
                            loading: loadingOutlets,
                            allowClear: !(u['role'] == 'seller' && outlets.length <= 1),
                            onChanged: (id) async {
                              setState(() => saleOutletId = id);
                              if (id != null) await _loadOutletProducts(id);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        _DateBtn(
                          value: saleDate,
                          onPick: (d) => setState(() => saleDate = d),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (saleOutletId == null)
                      Text('Выберите магазин', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))
                    else ...[
                      FilledButton.tonalIcon(
                        onPressed: loadingProducts ? null : _openProductPicker,
                        icon: const Icon(Icons.search_rounded),
                        label: Text(loadingProducts ? 'Загрузка товаров…' : 'Добавить товар'),
                      ),
                      const SizedBox(height: 12),
                      if (selectedProductIds.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            outletProducts.isEmpty ? 'Нет товаров в магазине' : 'Выберите товар из списка',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      else ...[
                        for (final pid in selectedProductIds)
                          _SaleLineCard(
                            dark: dark,
                            cs: cs,
                            pid: pid,
                            products: outletProducts,
                            edit: edits[pid]!,
                            onDelete: () => _removeProduct(pid),
                            onQtyChanged: (q) => setState(() => edits[pid] = edits[pid]!.copyWith(quantity: q)),
                            onPriceChanged: (p) => setState(() => edits[pid] = edits[pid]!.copyWith(unitPriceTjs: p)),
                          ),
                        const SizedBox(height: 10),
                        _CheckoutCard(
                          dark: dark,
                          cs: cs,
                          usdToTjs: usdToTjs,
                          totalTjs: cartTotalTjs,
                          paymentMethod: paymentMethod,
                          onPaymentChanged: (m) {
                            setState(() {
                              paymentMethod = m;
                              smsVerified = false;
                              checkoutVerificationId = null;
                              smsCode = '';
                              smsCooldownSec = 0;
                              _smsTimer?.cancel();
                            });
                          },
                          buyerName: buyerName,
                          onBuyerName: (v) => setState(() => buyerName = v),
                          buyerPhone9: buyerPhone9,
                          onBuyerPhone9: (v) {
                            final d = v.replaceAll(RegExp(r'[^\d]'), '');
                            setState(() => buyerPhone9 = d.length > 9 ? d.substring(0, 9) : d);
                          },
                          buyerComment: buyerComment,
                          onBuyerComment: (v) => setState(() => buyerComment = v),
                          cashPaidPartial: cashPaidPartial,
                          onCashPaid: (v) => setState(() => cashPaidPartial = v),
                          smsCooldownSec: smsCooldownSec,
                          smsVerified: smsVerified,
                          sendingSms: sendingSms,
                          verifyingSms: verifyingSms,
                          smsCode: smsCode,
                          onSmsCode: (v) => setState(() => smsCode = v.replaceAll(RegExp(r'\D'), '').substring(0, v.length.clamp(0, 8))),
                          hasVerification: checkoutVerificationId != null,
                          onRequestSms: smsCooldownSec > 0 ? null : _requestCheckoutSms,
                          onVerifySms: _verifyCheckoutSms,
                          canSubmit: canSubmitCart,
                          onSubmit: _submitCart,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                title: 'История продаж',
                child: Column(
                  children: [
                    Text('Период', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    QuickDateRangeChips(
                      colorScheme: cs,
                      selected: historyDatePreset,
                      onToday: () => _applyHistoryDateQuick('today'),
                      onWeek: () => _applyHistoryDateQuick('week'),
                      onMonth: () => _applyHistoryDateQuick('month'),
                      onPeriod: () => _applyHistoryDateQuick('period'),
                    ),
                    if (historyRange != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_fmtYmd(historyRange!.start)} — ${_fmtYmd(historyRange!.end)}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                          TextButton(
                            onPressed: _clearHistoryDateFilter,
                            child: const Text('Сбросить'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Поиск по товару',
                              isDense: true,
                            ),
                            onChanged: (v) => historySearch = v,
                            onSubmitted: (_) => _loadHistory(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Фильтры',
                          onPressed: () => _openHistoryFilters(),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (loadingHistory)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                            const SizedBox(width: 10),
                            Text('Загрузка…', style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    else
                      _HistoryTable(dark: dark, cs: cs, rows: sales),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHistoryFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final u = _user ?? const <String, dynamic>{};
        return _HistoryFilterSheet(
          outlets: outlets,
          allowOutletClear: !(u['role'] == 'seller' && outlets.length <= 1),
          outletId: filterOutletId,
          range: historyRange,
          datePresetKey: historyDatePreset,
          showTrash: showTrash,
          onApply: (outlet, range, trash, preset) {
            setState(() {
              filterOutletId = outlet;
              historyRange = range;
              showTrash = trash;
              historyDatePreset = preset;
            });
            _loadHistory();
          },
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: dark ? const Color(0xFF334155) : Colors.white,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _OutletDropdown extends StatelessWidget {
  const _OutletDropdown({
    required this.outlets,
    required this.value,
    required this.loading,
    required this.allowClear,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> outlets;
  final int? value;
  final bool loading;
  final bool allowClear;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      key: ValueKey<int?>(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Магазин',
        suffixIcon: loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : null,
      ),
      items: outlets
          .map((o) {
            final id = _asInt(o['id']);
            final name = (o['name'] ?? '').toString().trim();
            if (id == null) return null;
            return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
          })
          .whereType<DropdownMenuItem<int>>()
          .toList(),
      onChanged: (v) => onChanged(v),
    );
  }
}

class _DateBtn extends StatelessWidget {
  const _DateBtn({required this.value, required this.onPick});
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: value,
        );
        if (picked != null) onPick(picked);
      },
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Text(_fmtYmd(value), style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800)),
    );
  }
}

class _SaleLineCard extends StatelessWidget {
  const _SaleLineCard({
    required this.dark,
    required this.cs,
    required this.pid,
    required this.products,
    required this.edit,
    required this.onDelete,
    required this.onQtyChanged,
    required this.onPriceChanged,
  });

  final bool dark;
  final ColorScheme cs;
  final int pid;
  final List<Map<String, dynamic>> products;
  final _LineEdit edit;
  final VoidCallback onDelete;
  final ValueChanged<double> onQtyChanged;
  final ValueChanged<double> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final p = products.firstWhere((x) => _asInt(x['product_id']) == pid, orElse: () => const {});
    final name = (p['product_name'] ?? p['name'] ?? '—').toString();
    final costTjs = _asDouble(p['sale_price']) ?? 0;
    final inStore = _asDouble(p['quantity']) ?? 0;
    final sell = edit.unitPriceTjs;

    final invalid = sell <= 0 || sell < costTjs;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        border: Border.all(color: invalid ? const Color(0xFFEF4444).withValues(alpha: 0.55) : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cs.onSurface)),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFEF4444),
                  tooltip: 'Удалить',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text('Цена: ${costTjs.toStringAsFixed(0)} с.', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
                Text('В маг.: ${inStore.toStringAsFixed(inStore % 1 == 0 ? 0 : 3)} шт.', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Продаём за (с.)',
                      errorText: invalid ? 'Не ниже цены со склада' : null,
                    ),
                    controller: TextEditingController(text: sell.toStringAsFixed(0)),
                    onChanged: (v) {
                      final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onPriceChanged(n);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true, labelText: 'Кол-во'),
                    controller: TextEditingController(text: edit.quantity.toStringAsFixed(edit.quantity % 1 == 0 ? 0 : 3)),
                    onChanged: (v) {
                      final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onQtyChanged(n <= 0 ? 1 : n);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  const _CheckoutCard({
    required this.dark,
    required this.cs,
    required this.usdToTjs,
    required this.totalTjs,
    required this.paymentMethod,
    required this.onPaymentChanged,
    required this.buyerName,
    required this.onBuyerName,
    required this.buyerPhone9,
    required this.onBuyerPhone9,
    required this.buyerComment,
    required this.onBuyerComment,
    required this.cashPaidPartial,
    required this.onCashPaid,
    required this.smsCooldownSec,
    required this.smsVerified,
    required this.sendingSms,
    required this.verifyingSms,
    required this.smsCode,
    required this.onSmsCode,
    required this.hasVerification,
    required this.onRequestSms,
    required this.onVerifySms,
    required this.canSubmit,
    required this.onSubmit,
  });

  final bool dark;
  final ColorScheme cs;
  final double usdToTjs;
  final double totalTjs;

  final String paymentMethod;
  final ValueChanged<String> onPaymentChanged;

  final String buyerName;
  final ValueChanged<String> onBuyerName;
  final String buyerPhone9;
  final ValueChanged<String> onBuyerPhone9;
  final String buyerComment;
  final ValueChanged<String> onBuyerComment;

  final double cashPaidPartial;
  final ValueChanged<double> onCashPaid;

  final int smsCooldownSec;
  final bool smsVerified;
  final bool sendingSms;
  final bool verifyingSms;
  final String smsCode;
  final ValueChanged<String> onSmsCode;
  final bool hasVerification;
  final VoidCallback? onRequestSms;
  final VoidCallback onVerifySms;

  final bool canSubmit;
  final VoidCallback onSubmit;

  bool get needsContact => paymentMethod == 'nasiya' || paymentMethod == 'partial';

  @override
  Widget build(BuildContext context) {
    final totalUsd = usdToTjs > 0 ? (totalTjs / usdToTjs) : 0;
    final remainTjs = (paymentMethod == 'partial') ? (totalTjs - cashPaidPartial).clamp(0, totalTjs) : 0;
    final remainUsd = usdToTjs > 0 ? (remainTjs / usdToTjs) : 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(isDense: true, labelText: 'Имя покупателя (необязательно)', prefixIcon: Icon(Icons.person_outline_rounded)),
            onChanged: onBuyerName,
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Номер телефона',
              prefixText: '+992 ',
              prefixIcon: const Icon(Icons.phone_outlined),
              errorText: needsContact && buyerPhone9.replaceAll(RegExp(r'\\D'), '').length != 9 ? '9 цифр после +992' : null,
            ),
            keyboardType: TextInputType.number,
            onChanged: onBuyerPhone9,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: AppShape.br,
              color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Text('Итого', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('${totalTjs.toStringAsFixed(0)} с.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text('≈ ${totalUsd.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Способ оплаты', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 8),
          const SizedBox(height: 6),
          _PaymentSelector(
            value: paymentMethod,
            onChange: onPaymentChanged,
          ),
          if (paymentMethod == 'partial') ...[
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Оплачено наличными (с.)',
                errorText: (cashPaidPartial < 0 || cashPaidPartial > totalTjs) ? '0 .. ${totalTjs.toStringAsFixed(0)}' : null,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => onCashPaid(double.tryParse(v.replaceAll(',', '.')) ?? 0),
            ),
            const SizedBox(height: 8),
            Text(
              'Остаток в долг: ${remainTjs.toStringAsFixed(0)} с. (≈ ${remainUsd.toStringAsFixed(2)})',
              style: TextStyle(fontWeight: FontWeight.w900, color: dark ? const Color(0xFFFBBF24) : const Color(0xFFF97316)),
            ),
          ],
          if (needsContact) ...[
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(isDense: true, labelText: 'Комментарий для SMS *'),
              minLines: 2,
              maxLines: 3,
              onChanged: onBuyerComment,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: onRequestSms,
                  child: Text(smsCooldownSec > 0 ? 'Повторить через $smsCooldownSec c' : 'Отправить SMS'),
                ),
                if (hasVerification) ...[
                  SizedBox(
                    width: 140,
                    child: TextField(
                      decoration: const InputDecoration(isDense: true, labelText: 'Код из SMS'),
                      keyboardType: TextInputType.number,
                      onChanged: onSmsCode,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: verifyingSms ? null : onVerifySms,
                    child: Text(verifyingSms ? 'Проверка…' : 'Подтвердить'),
                  ),
                ],
              ],
            ),
            if (sendingSms) ...[
              const SizedBox(height: 8),
              Text('Отправляем SMS…', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (smsVerified) ...[
              const SizedBox(height: 8),
              Text('Код подтверждён', style: TextStyle(color: dark ? const Color(0xFF86EFAC) : const Color(0xFF059669), fontWeight: FontWeight.w900)),
            ],
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canSubmit ? onSubmit : null,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Завершить продажу'),
          ),
        ],
      ),
    );
  }
}

class _PayOpt {
  const _PayOpt({required this.keyName, required this.label, required this.icon});
  final String keyName;
  final String label;
  final IconData icon;
}

class _PaymentSelector extends StatelessWidget {
  const _PaymentSelector({required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opts = const [
      _PayOpt(keyName: 'cash', label: 'Наличные', icon: Icons.account_balance_outlined),
      _PayOpt(keyName: 'card', label: 'Карта', icon: Icons.credit_card_rounded),
      _PayOpt(keyName: 'nasiya', label: 'Насия', icon: Icons.wallet_outlined),
      _PayOpt(keyName: 'partial', label: 'Частично', icon: Icons.wallet_rounded),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final o in opts)
          InkWell(
            borderRadius: AppShape.br,
            onTap: () => onChange(o.keyName),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: AppShape.br,
                border: Border.all(
                  color: (value == o.keyName)
                      ? (dark ? const Color(0xFF93C5FD) : Theme.of(context).colorScheme.primary)
                      : (dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08)),
                ),
                color: (value == o.keyName)
                    ? (dark ? const Color(0xFF0F172A).withValues(alpha: 0.55) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08))
                    : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(o.icon, size: 18),
                  const SizedBox(width: 8),
                  Text(o.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.dark, required this.cs, required this.rows});
  final bool dark;
  final ColorScheme cs;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text('Нет продаж', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 12),
        dataTextStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 12),
        columns: const [
          DataColumn(label: Text('Дата')),
          DataColumn(label: Text('Магазин')),
          DataColumn(label: Text('Товар')),
          DataColumn(label: Text('Кол-во')),
        ],
        rows: rows.take(30).map((r) {
          final sold = (r['sold_at'] ?? '').toString();
          final outlet = (r['outlet_name'] ?? '').toString();
          final prod = (r['product_name'] ?? '').toString();
          final qty = r['quantity']?.toString() ?? '—';
          final totalReturned = _asDouble(r['total_returned']) ?? 0;
          final soldQty = _asDouble(r['quantity']) ?? 0;
          final bg = (soldQty > 0 && totalReturned >= soldQty)
              ? Colors.red.withValues(alpha: dark ? 0.20 : 0.10)
              : (totalReturned > 0 ? Colors.orange.withValues(alpha: dark ? 0.18 : 0.10) : null);
          return DataRow(
            color: bg == null ? null : WidgetStatePropertyAll(bg),
            cells: [
              DataCell(Text(sold.isEmpty ? '—' : sold.substring(0, sold.length.clamp(0, 10)))),
              DataCell(Text(outlet.isEmpty ? '—' : outlet)),
              DataCell(SizedBox(width: 220, child: Text(prod.isEmpty ? '—' : prod, overflow: TextOverflow.ellipsis))),
              DataCell(Text(totalReturned > 0 ? '${totalReturned.toStringAsFixed(0)} / ${soldQty.toStringAsFixed(0)}' : qty)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.selectedIds, required this.onPick});
  final List<Map<String, dynamic>> products;
  final Set<int> selectedIds;
  final ValueChanged<int> onPick;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final items = widget.products.where((p) {
      final name = (p['product_name'] ?? p['name'] ?? '').toString().toLowerCase();
      final model = (p['model'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      final s = q.trim().toLowerCase();
      if (s.isEmpty) return true;
      return name.contains(s) || model.contains(s) || sku.contains(s);
    }).take(250).toList();

    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1220) : Colors.white,
        borderRadius: AppShape.sheetTop,
      ),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 12,
        bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 3, decoration: AppShape.sheetHandle(Colors.white.withValues(alpha: dark ? 0.14 : 0.22))),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск по названию, модели, артикулу…', isDense: true),
            onChanged: (v) => setState(() => q = v),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
              itemBuilder: (ctx, i) {
                final p = items[i];
                final pid = _asInt(p['product_id']);
                if (pid == null) return const SizedBox.shrink();
                final name = (p['product_name'] ?? p['name'] ?? '—').toString();
                final model = (p['model'] ?? '').toString();
                final sku = (p['sku'] ?? '').toString();
                final sub = [model, sku].where((x) => x.trim().isNotEmpty).join(' · ');
                final selected = widget.selectedIds.contains(pid);
                return ListTile(
                  dense: true,
                  title: Text(name, style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                  subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: selected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)) : const Icon(Icons.add_circle_outline_rounded),
                  onTap: () => widget.onPick(pid),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterSheet extends StatefulWidget {
  const _HistoryFilterSheet({
    required this.outlets,
    required this.allowOutletClear,
    required this.outletId,
    required this.range,
    required this.datePresetKey,
    required this.showTrash,
    required this.onApply,
  });

  final List<Map<String, dynamic>> outlets;
  final bool allowOutletClear;
  final int? outletId;
  final DateTimeRange? range;
  final String? datePresetKey;
  final bool showTrash;
  final void Function(int? outlet, DateTimeRange? range, bool trash, String? preset) onApply;

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  int? outlet;
  DateTimeRange? range;
  String? datePreset;
  bool trash = false;

  @override
  void initState() {
    super.initState();
    outlet = widget.outletId;
    range = widget.range;
    datePreset = widget.datePresetKey;
    trash = widget.showTrash;
  }

  void _applyQuick(String kind) {
    if (kind == 'period') {
      _openRangePicker();
      return;
    }
    final r = DateRangePresets.rangeForPreset(kind);
    if (r == null) return;
    setState(() {
      datePreset = kind;
      range = r;
    });
  }

  Future<void> _openRangePicker() async {
    final now = DateTime.now();
    final initial = range ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: 'Период',
      cancelText: 'Отмена',
      confirmText: 'ОК',
    );
    if (picked != null && mounted) {
      setState(() {
        range = picked;
        datePreset = 'period';
      });
    }
  }

  void _clearPeriod() {
    setState(() {
      range = null;
      datePreset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1220) : Colors.white,
        borderRadius: AppShape.sheetTop,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 36, height: 3, decoration: AppShape.sheetHandle(Colors.white.withValues(alpha: dark ? 0.14 : 0.22))),
            const SizedBox(height: 12),
            Text('Фильтры', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 12),
            Text('Период', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            QuickDateRangeChips(
              colorScheme: cs,
              selected: datePreset,
              onToday: () => _applyQuick('today'),
              onWeek: () => _applyQuick('week'),
              onMonth: () => _applyQuick('month'),
              onPeriod: () => _applyQuick('period'),
            ),
            if (range != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_fmtYmd(range!.start)} — ${_fmtYmd(range!.end)}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(onPressed: _clearPeriod, child: const Text('Сбросить')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey<int?>(outlet),
              initialValue: outlet,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, labelText: 'Магазин'),
              items: [
                if (widget.allowOutletClear) const DropdownMenuItem<int>(value: null, child: Text('Все магазины')),
                ...widget.outlets
                    .map((o) {
                      final id = _asInt(o['id']);
                      final name = (o['name'] ?? '').toString().trim();
                      if (id == null) return null;
                      return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
                    })
                    .whereType<DropdownMenuItem<int>>(),
              ],
              onChanged: (v) => setState(() => outlet = v),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: trash,
              onChanged: (v) => setState(() => trash = v),
              title: const Text('В корзине'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onApply(outlet, range, trash, datePreset);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEdit {
  const _LineEdit({required this.quantity, required this.unitPriceTjs, required this.currency});
  final double quantity;
  final double unitPriceTjs;
  final String currency;

  _LineEdit copyWith({double? quantity, double? unitPriceTjs, String? currency}) => _LineEdit(
        quantity: quantity ?? this.quantity,
        unitPriceTjs: unitPriceTjs ?? this.unitPriceTjs,
        currency: currency ?? this.currency,
      );
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

double? _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

String _fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

