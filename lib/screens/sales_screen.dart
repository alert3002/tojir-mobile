import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_brand.dart';
import '../theme/app_shape.dart';
import '../utils/number_format.dart';
import '../utils/permissions.dart';
import '../utils/product_scan_utils.dart';
import '../widgets/app_scaffold.dart';

const _salesMobilePageSize = 10;

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
  int? filterOutletId;
  bool showTrash = false;
  List<Map<String, dynamic>> sales = const [];

  String mobileViewTab = 'sale';
  int historyMobilePage = 1;
  final _saleScanCtrl = TextEditingController();
  final _historySearchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _checkoutKey = GlobalKey();
  String checkoutCurrency = 'TJS';
  int? deletingId;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  List<Map<String, dynamic>> get _availableOutletProducts =>
      outletProducts.where((p) => (_asDouble(p['quantity']) ?? 0) > 0).toList();

  bool _showStorePicker(Map<String, dynamic> u) => u['role'] != 'seller' || outlets.length > 1;

  String _saleOutletName() {
    final id = saleOutletId;
    if (id == null) return '—';
    for (final o in outlets) {
      if (_asInt(o['id']) == id) {
        final name = (o['name'] ?? '').toString().trim();
        return name.isEmpty ? 'Магазин $id' : name;
      }
    }
    return 'Магазин $id';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final u = _user;
      final args = ModalRoute.of(context)?.settings.arguments;
      int? presetOutlet;
      var presetTab = '';
      if (args is Map) {
        presetOutlet = _asInt(args['outlet']);
        final tab = args['tab'];
        if (tab is String) presetTab = tab;
      }
      if (presetTab == 'sale') {
        setState(() => mobileViewTab = 'sale');
      } else if (u != null && (u['role'] == 'businessman' || u['role'] == 'platform')) {
        setState(() => mobileViewTab = 'history');
      }
      if (presetOutlet != null) {
        setState(() => saleOutletId = presetOutlet);
      }
      await _loadRate();
      await _loadOutlets();
      await _loadHistory();
    });
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    _saleScanCtrl.dispose();
    _historySearchCtrl.dispose();
    _scrollCtrl.dispose();
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
      items.add({'product': pid, 'quantity': e.quantity, 'unit_price': e.unitPriceTjs, 'currency': e.currency});
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

  Future<void> _pickHistoryDateRange() async {
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
    setState(() => historyRange = picked);
    await _loadHistory();
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
        setState(() {
          sales = items;
          historyMobilePage = 1;
        });
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

  void _handleSaleScan(String raw) {
    final p = findOutletProductByCode(raw, _availableOutletProducts);
    if (p == null) {
      _snack('Товар не найден', error: true);
      return;
    }
    final pid = _asInt(p['product_id']);
    if (pid == null) return;
    _addProduct(pid);
    setState(() => _saleScanCtrl.clear());
  }

  void _scrollToCheckout() {
    final ctx = _checkoutKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  Future<void> _onDeleteSale(Map<String, dynamic> record) async {
    final isTrash = showTrash;
    final qty = _asDouble(record['quantity']) ?? 0;
    final qtyStr = qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(3);
    final name = (record['product_name'] ?? '—').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTrash ? 'Удалить продажу навсегда?' : 'Переместить продажу в корзину?'),
        content: Text(
          isTrash
              ? 'Товар: $name, кол-во: $qtyStr.\nОстаток вернётся в магазин. Запись будет удалена безвозвратно.'
              : 'Товар: $name, кол-во: $qtyStr.\nПродажа будет перемещена в корзину.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isTrash ? 'Удалить навсегда' : 'В корзину'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = record['id'];
    if (id == null) return;
    setState(() => deletingId = _asInt(id));
    try {
      final api = context.read<ApiClient>();
      final path = isTrash ? 'inventory/sales/$id/?force=1' : 'inventory/sales/$id/';
      final res = await api.delete(path);
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) throw Exception('Ошибка удаления');
      _snack(isTrash ? 'Продажа удалена навсегда' : 'Продажа в корзине');
      await _loadHistory();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  Future<void> _restoreSale(Map<String, dynamic> record) async {
    final id = record['id'];
    if (id == null) return;
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('inventory/sales/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('Не удалось восстановить');
      _snack('Продажа восстановлена');
      await _loadHistory();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _openEditSale(Map<String, dynamic> record) async {
    final priceTjs = _asDouble(record['product_sale_price']) ?? 0;
    final stockQty = _asDouble(record['outlet_stock_quantity']) ?? 0;
    final currentQty = _asDouble(record['quantity']) ?? 0;
    final maxQty = stockQty + currentQty;
    var qty = currentQty;
    var currency = (record['currency'] as String?) ?? 'TJS';
    var soldAt = DateTime.tryParse((record['sold_at'] ?? '').toString().substring(0, 10)) ?? DateTime.now();
    var loading = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final unitPrice = currency == 'USD' && usdToTjs > 0 ? priceTjs / usdToTjs : priceTjs;
          final sum = qty * unitPrice;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                borderRadius: AppShape.sheetTop,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Изменить продажу', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(
                      '${record['product_name'] ?? '—'} — ${record['outlet_name'] ?? '—'}',
                      style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Количество',
                        helperText: 'Макс. ${maxQty.toStringAsFixed(maxQty % 1 == 0 ? 0 : 3)} (остаток в магазине + текущая продажа)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      controller: TextEditingController(text: qty.toString()),
                      onChanged: (v) => qty = double.tryParse(v.replaceAll(',', '.')) ?? qty,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: currency,
                      decoration: const InputDecoration(labelText: 'Валюта'),
                      items: const [
                        DropdownMenuItem(value: 'TJS', child: Text('TJS')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (v) => setSheet(() => currency = v ?? 'TJS'),
                    ),
                    const SizedBox(height: 8),
                    Text('За единицу: ${unitPrice > 0 ? '${unitPrice.toStringAsFixed(2)} $currency' : '—'}'),
                    Text('Сумма: ${sum > 0 ? '${sum.toStringAsFixed(2)} $currency' : '—'}'),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: soldAt,
                        );
                        if (picked != null) setSheet(() => soldAt = picked);
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(_fmtYmd(soldAt)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: (loading || qty <= 0 || qty > maxQty)
                                ? null
                                : () async {
                                    setSheet(() => loading = true);
                                    try {
                                      final api = context.read<ApiClient>();
                                      final res = await api.patch(
                                        'inventory/sales/${record['id']}/',
                                        body: {
                                          'quantity': qty,
                                          'unit_price': unitPrice,
                                          'currency': currency,
                                          'sold_at': _fmtYmd(soldAt),
                                        },
                                      );
                                      if (!ctx.mounted) return;
                                      if (res.statusCode != 200) {
                                        final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
                                        throw Exception((data is Map ? data['detail'] : null)?.toString() ?? 'Ошибка');
                                      }
                                      Navigator.pop(ctx);
                                      _snack('Продажа изменена');
                                      await _loadHistory();
                                    } catch (e) {
                                      _snack(e.toString(), error: true);
                                    } finally {
                                      if (ctx.mounted) setSheet(() => loading = false);
                                    }
                                  },
                            child: Text(loading ? 'Сохранение…' : 'Сохранить'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openReturnSale(Map<String, dynamic> record) async {
    final sold = _asDouble(record['quantity']) ?? 0;
    final already = _asDouble(record['total_returned']) ?? 0;
    final maxReturnable = (sold - already).clamp(0, sold);
    var qty = maxReturnable > 0 ? maxReturnable : 1.0;
    var returnedAt = DateTime.now();
    final reasonCtrl = TextEditingController();
    var loading = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
              borderRadius: AppShape.sheetTop,
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Оформить возврат', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    '${record['product_name'] ?? '—'} — ${record['outlet_name'] ?? '—'}, продано: ${sold.toStringAsFixed(sold % 1 == 0 ? 0 : 3)}'
                    '${already > 0 ? ', возвращено: ${already.toStringAsFixed(0)}, можно вернуть: ${maxReturnable.toStringAsFixed(0)}' : ''}',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(labelText: 'Количество к возврату'),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: qty.toStringAsFixed(0)),
                    onChanged: (v) => qty = double.tryParse(v) ?? qty,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: returnedAt,
                      );
                      if (picked != null) setSheet(() => returnedAt = picked);
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(_fmtYmd(returnedAt)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Причина возврата'),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: (loading || qty <= 0 || qty > maxReturnable)
                              ? null
                              : () async {
                                  setSheet(() => loading = true);
                                  try {
                                    final api = context.read<ApiClient>();
                                    final res = await api.post(
                                      'inventory/returns/',
                                      body: {
                                        'sale': record['id'],
                                        'quantity_returned': qty,
                                        'returned_at': _fmtYmd(returnedAt),
                                        if (reasonCtrl.text.trim().isNotEmpty) 'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                    if (!ctx.mounted) return;
                                    if (res.statusCode != 200 && res.statusCode != 201) {
                                      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
                                      throw Exception((data is Map ? data['detail'] : null)?.toString() ?? 'Ошибка');
                                    }
                                    Navigator.pop(ctx);
                                    _snack('Возврат оформлен');
                                    await _loadHistory();
                                  } catch (e) {
                                    _snack(e.toString(), error: true);
                                  } finally {
                                    if (ctx.mounted) setSheet(() => loading = false);
                                  }
                                },
                          child: Text(loading ? 'Оформление…' : 'Оформить возврат'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
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

    final showStore = _showStorePicker(u);
    final isBusinessman = u['role'] == 'businessman' || u['role'] == 'platform';
    final stickyBar = mobileViewTab == 'sale' && selectedProductIds.isNotEmpty;
    final historySlice = sales.skip((historyMobilePage - 1) * _salesMobilePageSize).take(_salesMobilePageSize).toList();

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await _loadRate();
                await _loadOutlets();
                await _loadHistory();
              },
              child: ListView(
                controller: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(12, 10, 12, stickyBar ? 88 : 14),
                children: [
                  Text('Продажа', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.2)),
                  const SizedBox(height: 10),
                  _SalesMobileTabs(
                    active: mobileViewTab,
                    cartCount: selectedProductIds.length,
                    onSale: () => setState(() => mobileViewTab = 'sale'),
                    onHistory: () => setState(() => mobileViewTab = 'history'),
                  ),
                  if (mobileViewTab == 'sale') ...[
                    _Card(
                      title: 'Оформить продажу',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (u['role'] == 'seller' && !showStore) ...[
                            _SellerContextBanner(name: _saleOutletName()),
                            const SizedBox(height: 10),
                          ],
                          if (showStore) ...[
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
                                const SizedBox(width: 8),
                                _DateBtn(value: saleDate, onPick: (d) => setState(() => saleDate = d)),
                              ],
                            ),
                          ] else
                            _DateBtn(value: saleDate, onPick: (d) => setState(() => saleDate = d)),
                          if (saleOutletId == null) ...[
                            const SizedBox(height: 10),
                            Text('Выберите магазин', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                          ] else ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF2563EB).withValues(alpha: 0.14),
                                    (dark ? const Color(0xFF0F172A) : cs.surfaceContainer).withValues(alpha: 0.55),
                                  ],
                                ),
                                border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.28)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFFBFDBFE)),
                                      const SizedBox(width: 8),
                                      Text('Сканер', style: TextStyle(fontWeight: FontWeight.w600, color: dark ? const Color(0xFFBFDBFE) : cs.primary)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _saleScanCtrl,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            hintText: 'Сканируйте QR, штрих-код, IMEI',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-./:?=&%+\s]'))],
                                          onSubmitted: _handleSaleScan,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 44,
                                        width: 44,
                                        child: FilledButton(
                                          onPressed: () => _handleSaleScan(_saleScanCtrl.text),
                                          style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          child: const Icon(Icons.center_focus_weak_rounded, size: 22),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: loadingProducts ? null : _openProductPicker,
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: dark ? Colors.white.withValues(alpha: 0.04) : cs.surfaceContainerHighest,
                                    border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          loadingProducts ? 'Загрузка…' : (u['role'] == 'seller' ? 'Найти товар…' : 'Поиск по названию, артикулу, коду…'),
                                          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                                        ),
                                      ),
                                      Icon(Icons.expand_more_rounded, size: 22, color: cs.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (selectedProductIds.isEmpty) ...[
                              const SizedBox(height: 10),
                              _SalesEmptyHint(
                                loading: loadingOutlets || loadingProducts,
                                noOutlet: saleOutletId == null,
                                hasProducts: _availableOutletProducts.isNotEmpty,
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              for (final pid in selectedProductIds)
                                _SaleLineCard(
                                  dark: dark,
                                  cs: cs,
                                  pid: pid,
                                  products: outletProducts,
                                  edit: edits[pid]!,
                                  isBusinessman: isBusinessman,
                                  onDelete: () => _removeProduct(pid),
                                  onQtyChanged: (q) => setState(() => edits[pid] = edits[pid]!.copyWith(quantity: q)),
                                  onPriceChanged: (p) => setState(() => edits[pid] = edits[pid]!.copyWith(unitPriceTjs: p)),
                                  onCurrencyChanged: (c) => setState(() => edits[pid] = edits[pid]!.copyWith(currency: c)),
                                ),
                              const SizedBox(height: 10),
                              KeyedSubtree(
                                key: _checkoutKey,
                                child: _CheckoutCard(
                                  dark: dark,
                                  cs: cs,
                                  outletName: _saleOutletName(),
                                  saleDate: saleDate,
                                  itemCount: selectedProductIds.length,
                                  usdToTjs: usdToTjs,
                                  totalTjs: cartTotalTjs,
                                  checkoutCurrency: checkoutCurrency,
                                  onCheckoutCurrency: (c) => setState(() => checkoutCurrency = c),
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
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (mobileViewTab == 'history') ...[
                    _Card(
                      title: 'История продаж',
                      child: Column(
                        children: [
                          _SalesHistoryFilters(
                            cs: cs,
                            dark: dark,
                            searchCtrl: _historySearchCtrl,
                            onSearch: (v) {
                              historySearch = v;
                              setState(() => historyMobilePage = 1);
                              _loadHistory();
                            },
                            range: historyRange,
                            onPickRange: _pickHistoryDateRange,
                            onClearRange: () {
                              setState(() => historyRange = null);
                              _loadHistory();
                            },
                            showStore: showStore,
                            outlets: outlets,
                            outletId: filterOutletId,
                            allowOutletClear: !(u['role'] == 'seller' && outlets.length <= 1),
                            onOutletChanged: (id) {
                              setState(() => filterOutletId = id);
                              _loadHistory();
                            },
                            showTrash: showTrash,
                            onTrashChanged: (v) {
                              setState(() => showTrash = v);
                              _loadHistory();
                            },
                          ),
                          const SizedBox(height: 10),
                          if (loadingHistory && sales.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
                            )
                          else
                            _SaleHistoryMobileList(
                              dark: dark,
                              cs: cs,
                              rows: historySlice,
                              showStore: showStore,
                              showTrash: showTrash,
                              deletingId: deletingId,
                              onEdit: _openEditSale,
                              onReturn: _openReturnSale,
                              onDelete: _onDeleteSale,
                              onRestore: _restoreSale,
                            ),
                          if (!loadingHistory && sales.length > _salesMobilePageSize) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: historyMobilePage > 1 ? () => setState(() => historyMobilePage--) : null,
                                  icon: const Icon(Icons.chevron_left_rounded),
                                ),
                                Text('$historyMobilePage / ${(sales.length / _salesMobilePageSize).ceil()}'),
                                IconButton(
                                  onPressed: historyMobilePage * _salesMobilePageSize < sales.length
                                      ? () => setState(() => historyMobilePage++)
                                      : null,
                                  icon: const Icon(Icons.chevron_right_rounded),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (stickyBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SalesMobileBar(
                  count: selectedProductIds.length,
                  totalTjs: cartTotalTjs,
                  onCheckout: _scrollToCheckout,
                ),
              ),
          ],
        ),
      ),
    );
  }

}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: AppBrand.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25)))),
            child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: child),
        ],
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
        labelText: 'Магазин',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        visualDensity: VisualDensity.standard,
      ),
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

class _SalesMobileTabs extends StatelessWidget {
  const _SalesMobileTabs({
    required this.active,
    required this.cartCount,
    required this.onSale,
    required this.onHistory,
  });

  final String active;
  final int cartCount;
  final VoidCallback onSale;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(child: _SalesTabButton(label: 'Оформить', active: active == 'sale', badge: cartCount, onTap: onSale, dark: dark)),
        const SizedBox(width: 8),
        Expanded(child: _SalesTabButton(label: 'История', active: active == 'history', onTap: onHistory, dark: dark)),
      ],
    );
  }
}

class _SalesTabButton extends StatelessWidget {
  const _SalesTabButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.dark,
    this.badge = 0,
  });

  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final inactiveBorder = dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);
    final inactiveBg = dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
    final inactiveFg = dark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF475569);
    return Material(
      color: active ? AppBrand.primaryBlue.withValues(alpha: dark ? 0.22 : 0.12) : inactiveBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppBrand.primaryBlue.withValues(alpha: 0.55) : inactiveBorder),
            boxShadow: active ? [BoxShadow(color: AppBrand.primaryBlue.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 4))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? (dark ? const Color(0xFFF1F5F9) : AppBrand.primaryBlue) : inactiveFg)),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: AppBrand.primaryBlue, borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.center,
                  child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesHistoryFilters extends StatelessWidget {
  const _SalesHistoryFilters({
    required this.cs,
    required this.dark,
    required this.searchCtrl,
    required this.onSearch,
    required this.range,
    required this.onPickRange,
    required this.onClearRange,
    required this.showStore,
    required this.outlets,
    required this.outletId,
    required this.allowOutletClear,
    required this.onOutletChanged,
    required this.showTrash,
    required this.onTrashChanged,
  });

  final ColorScheme cs;
  final bool dark;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final DateTimeRange? range;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final bool showStore;
  final List<Map<String, dynamic>> outlets;
  final int? outletId;
  final bool allowOutletClear;
  final ValueChanged<int?> onOutletChanged;
  final bool showTrash;
  final ValueChanged<bool> onTrashChanged;

  @override
  Widget build(BuildContext context) {
    final fieldBorder = dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchCtrl,
          decoration: InputDecoration(
            hintText: 'Поиск по товару',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search_rounded, size: 20),
              onPressed: () => onSearch(searchCtrl.text),
            ),
          ),
          onChanged: onSearch,
          onSubmitted: onSearch,
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPickRange,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fieldBorder),
                color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      range != null ? _fmtYmd(range!.start) : 'Дата от',
                      style: TextStyle(fontSize: 13, color: range != null ? cs.onSurface : cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  Expanded(
                    child: Text(
                      range != null ? _fmtYmd(range!.end) : 'Дата до',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 13, color: range != null ? cs.onSurface : cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (range != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onClearRange, child: const Text('Сбросить даты')),
          ),
        ],
        if (showStore) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey<int?>(outletId),
            initialValue: outletId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Магазин (все)',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              if (allowOutletClear) const DropdownMenuItem<int>(value: null, child: Text('Все магазины')),
              ...outlets
                  .map((o) {
                    final id = _asInt(o['id']);
                    final name = (o['name'] ?? '').toString().trim();
                    if (id == null) return null;
                    return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
                  })
                  .whereType<DropdownMenuItem<int>>(),
            ],
            onChanged: onOutletChanged,
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Switch(
              value: showTrash,
              onChanged: onTrashChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Text('В корзине', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _SalesMobileBar extends StatelessWidget {
  const _SalesMobileBar({required this.count, required this.totalTjs, required this.onCheckout});

  final int count;
  final double totalTjs;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1 ? 'товар' : 'товара';
    return Material(
      color: const Color(0xF50C111C),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count $noun', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55))),
                    Text(
                      '${formatRuMoney(totalTjs)} с.',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF4ADE80), height: 1.2),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onCheckout,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('К оплате', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerContextBanner extends StatelessWidget {
  const _SellerContextBanner({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppBrand.primaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 18, color: Color(0xFFE2E8F0)),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0)))),
        ],
      ),
    );
  }
}

class _SalesEmptyHint extends StatelessWidget {
  const _SalesEmptyHint({required this.loading, required this.noOutlet, required this.hasProducts});

  final bool loading;
  final bool noOutlet;
  final bool hasProducts;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? 'Загрузка…'
        : noOutlet
            ? 'Выберите магазин'
            : hasProducts
                ? 'Выберите товар или отсканируйте код'
                : 'В этом магазине нет товаров в наличии';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ],
      ),
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
    required this.isBusinessman,
    required this.onDelete,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onCurrencyChanged,
  });

  final bool dark;
  final ColorScheme cs;
  final int pid;
  final List<Map<String, dynamic>> products;
  final _LineEdit edit;
  final bool isBusinessman;
  final VoidCallback onDelete;
  final ValueChanged<double> onQtyChanged;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    final p = products.firstWhere((x) => _asInt(x['product_id']) == pid, orElse: () => const {});
    final name = (p['product_name'] ?? p['name'] ?? '—').toString();
    final subline = _productSubline(p);
    final costTjs = _asDouble(p['sale_price']) ?? 0;
    final inStore = _asDouble(p['quantity']) ?? 0;
    final sell = edit.unitPriceTjs;

    final invalid = sell <= 0 || sell < costTjs;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark ? AppBrand.darkRow : cs.surfaceContainer,
        border: Border.all(
          color: invalid
              ? const Color(0xFFEF4444).withValues(alpha: 0.55)
              : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.3)),
                      if (subline != null) ...[
                        const SizedBox(height: 2),
                        Text(subline, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: const Color(0xFFEF4444),
                  tooltip: 'Удалить',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (isBusinessman) Text('Склад: ${costTjs.toStringAsFixed(0)} с.', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
                Text('В магазине: ${inStore.toStringAsFixed(inStore % 1 == 0 ? 0 : 3)} шт.', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
                if (isBusinessman && sell > costTjs && costTjs > 0)
                  Text('+${(sell - costTjs).toStringAsFixed(0)} с.', style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Цена',
                      suffixText: 'с.',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      errorText: invalid ? 'Не ниже цены со склада' : null,
                    ),
                    controller: TextEditingController(text: sell.toStringAsFixed(0)),
                    onChanged: (v) {
                      final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onPriceChanged(n);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: DropdownButtonFormField<String>(
                    initialValue: edit.currency,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Валюта', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'TJS', child: Text('TJS')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => onCurrencyChanged(v ?? 'TJS'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Кол-во', isDense: true),
                    controller: TextEditingController(text: edit.quantity.toStringAsFixed(edit.quantity % 1 == 0 ? 0 : 3)),
                    onChanged: (v) {
                      final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onQtyChanged(n <= 0 ? 1 : n);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Сумма строки', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                Text('${(sell * edit.quantity).toStringAsFixed(0)} с.', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
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
    required this.outletName,
    required this.saleDate,
    required this.itemCount,
    required this.usdToTjs,
    required this.totalTjs,
    required this.checkoutCurrency,
    required this.onCheckoutCurrency,
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
  final String outletName;
  final DateTime saleDate;
  final int itemCount;
  final double usdToTjs;
  final double totalTjs;
  final String checkoutCurrency;
  final ValueChanged<String> onCheckoutCurrency;

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

  String get _itemCountLabel {
    if (itemCount == 1) return '1 товар';
    return '$itemCount товара';
  }

  String get _smsPreview {
    if (!needsContact) return '';
    if (paymentMethod == 'partial') {
      final paid = cashPaidPartial;
      final debt = (totalTjs - paid).clamp(0, totalTjs);
      return _fillSmsTemplate('partial_sale', {
        'paid': paid.toStringAsFixed(0),
        'debt': debt.toStringAsFixed(0),
        'code': '••••',
      });
    }
    return _fillSmsTemplate('nasiya_sale', {
      'amount': totalTjs.toStringAsFixed(0),
      'code': '••••',
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalUsd = usdToTjs > 0 ? (totalTjs / usdToTjs) : 0;
    final remainTjs = (paymentMethod == 'partial') ? (totalTjs - cashPaidPartial).clamp(0, totalTjs) : 0.0;
    final receiptBg = dark ? AppBrand.darkCard : cs.surfaceContainerLow;
    final dd = saleDate.day.toString().padLeft(2, '0');
    final mm = saleDate.month.toString().padLeft(2, '0');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: receiptBg,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              border: Border(bottom: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08), style: BorderStyle.solid)),
            ),
            child: Column(
              children: [
                Text('ЧЕК', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2, color: cs.onSurface)),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text(outletName, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    Text('$dd.$mm.${saleDate.year}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_itemCountLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: needsContact ? 'Имя покупателя' : 'Имя покупателя (необяз.)',
                    hintText: 'Введите имя',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  onChanged: onBuyerName,
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: needsContact ? 'Телефон' : 'Телефон (необяз.)',
                    prefixText: '+992 ',
                    hintText: '90XXXXXXX',
                    errorText: needsContact && buyerPhone9.replaceAll(RegExp(r'\D'), '').length != 9 ? '9 цифр после +992' : null,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  onChanged: onBuyerPhone9,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF22C55E).withValues(alpha: 0.14),
                        const Color(0xFF2563EB).withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ИТОГО К ОПЛАТЕ',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: cs.onSurfaceVariant),
                            ),
                          ),
                          DropdownButton<String>(
                            value: checkoutCurrency,
                            underline: const SizedBox.shrink(),
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 'TJS', child: Text('TJS')),
                              DropdownMenuItem(value: 'USD', child: Text('USD')),
                            ],
                            onChanged: (v) => onCheckoutCurrency(v ?? 'TJS'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        checkoutCurrency == 'USD' ? '\$${totalUsd.toStringAsFixed(2)}' : '${formatRuMoney(totalTjs)} с.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF4ADE80), height: 1.15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        checkoutCurrency == 'USD' ? '≈ ${formatRuMoney(totalTjs)} с.' : '≈ \$${totalUsd.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('Способ оплаты', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface)),
                const SizedBox(height: 8),
                _PaymentSelector(value: paymentMethod, onChange: onPaymentChanged),
                if (paymentMethod == 'partial') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: dark ? AppBrand.darkRow : cs.surfaceContainer,
                      border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Оплачено наличными', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: 'с.',
                            errorText: (cashPaidPartial < 0 || cashPaidPartial > totalTjs) ? '0 .. ${totalTjs.toStringAsFixed(0)}' : null,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => onCashPaid(double.tryParse(v.replaceAll(',', '.')) ?? 0),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Остаток в долг', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                            Text(
                              '${remainTjs.toStringAsFixed(0)} с.',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: dark ? const Color(0xFFFBBF24) : const Color(0xFFF97316)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (needsContact) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Комментарий для SMS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const Text(' *', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Согласие на покупку, условия насия…',
                      counterText: '${buyerComment.length} / 500',
                    ),
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 500,
                    onChanged: onBuyerComment,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: onRequestSms,
                        child: Text(smsCooldownSec > 0 ? 'Повторить через $smsCooldownSec с' : 'Отправить SMS'),
                      ),
                      if (hasVerification) ...[
                        SizedBox(
                          width: 130,
                          child: TextField(
                            decoration: const InputDecoration(isDense: true, hintText: 'Код из SMS'),
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
                  if (_smsPreview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Шаблон SMS: $_smsPreview', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35)),
                  ],
                  if (smsVerified) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: dark ? const Color(0xFF86EFAC) : const Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text('Код подтверждён', style: TextStyle(color: dark ? const Color(0xFF86EFAC) : const Color(0xFF059669), fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: canSubmit ? onSubmit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      disabledBackgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Завершить продажу', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayOpt {
  const _PayOpt({required this.keyName, required this.label, required this.icon, required this.tone});
  final String keyName;
  final String label;
  final IconData icon;
  final String tone;
}

class _PaymentSelector extends StatelessWidget {
  const _PaymentSelector({required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  static (Color border, Color bg, Color fg) _toneColors(String tone, bool active) {
    if (!active) return (Colors.transparent, Colors.transparent, Colors.transparent);
    switch (tone) {
      case 'card':
        return (const Color(0xFF3B82F6), const Color(0xFF3B82F6).withValues(alpha: 0.28), const Color(0xFF93C5FD));
      case 'nasiya':
        return (const Color(0xFFF97316), const Color(0xFFF97316).withValues(alpha: 0.28), const Color(0xFFFDBA74));
      case 'partial':
        return (const Color(0xFFA855F7), const Color(0xFFA855F7).withValues(alpha: 0.28), const Color(0xFFD8B4FE));
      default:
        return (const Color(0xFF22C55E), const Color(0xFF22C55E).withValues(alpha: 0.28), const Color(0xFF86EFAC));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opts = const [
      _PayOpt(keyName: 'cash', label: 'Наличные', icon: Icons.account_balance_outlined, tone: 'cash'),
      _PayOpt(keyName: 'card', label: 'Карта', icon: Icons.credit_card_rounded, tone: 'card'),
      _PayOpt(keyName: 'nasiya', label: 'Насия', icon: Icons.wallet_outlined, tone: 'nasiya'),
      _PayOpt(keyName: 'partial', label: 'Частично', icon: Icons.wallet_rounded, tone: 'partial'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.45,
      children: [
        for (final o in opts)
          Builder(
            builder: (context) {
              final active = value == o.keyName;
              final (border, bg, fg) = _toneColors(o.tone, active);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChange(o.keyName),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: active ? bg : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                      border: Border.all(
                        color: active ? border : (dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (active)
                          const Positioned(
                            top: 6,
                            right: 8,
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: Color(0xFF22C55E),
                              child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
                            ),
                          ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(o.icon, size: 22, color: active ? fg : (dark ? const Color(0xFFF1F5F9) : const Color(0xFF334155))),
                              const SizedBox(height: 6),
                              Text(
                                o.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? fg : (dark ? const Color(0xFFF1F5F9) : const Color(0xFF334155))),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SaleHistoryMobileList extends StatelessWidget {
  const _SaleHistoryMobileList({
    required this.dark,
    required this.cs,
    required this.rows,
    required this.showStore,
    required this.showTrash,
    required this.deletingId,
    required this.onEdit,
    required this.onReturn,
    required this.onDelete,
    required this.onRestore,
  });

  final bool dark;
  final ColorScheme cs;
  final List<Map<String, dynamic>> rows;
  final bool showStore;
  final bool showTrash;
  final int? deletingId;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onReturn;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final ValueChanged<Map<String, dynamic>> onRestore;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Text('Нет продаж', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return Column(
      children: [
        for (final r in rows)
          _SaleHistoryMobileCard(
            dark: dark,
            cs: cs,
            record: r,
            showStore: showStore,
            showTrash: showTrash,
            deleting: deletingId == _asInt(r['id']),
            onEdit: () => onEdit(r),
            onReturn: () => onReturn(r),
            onDelete: () => onDelete(r),
            onRestore: () => onRestore(r),
          ),
      ],
    );
  }
}

class _SaleHistoryMobileCard extends StatelessWidget {
  const _SaleHistoryMobileCard({
    required this.dark,
    required this.cs,
    required this.record,
    required this.showStore,
    required this.showTrash,
    required this.deleting,
    required this.onEdit,
    required this.onReturn,
    required this.onDelete,
    required this.onRestore,
  });

  final bool dark;
  final ColorScheme cs;
  final Map<String, dynamic> record;
  final bool showStore;
  final bool showTrash;
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback onReturn;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final qty = _asDouble(record['quantity']) ?? 0;
    final ret = _asDouble(record['total_returned']) ?? 0;
    final status = _getSaleReturnStatus(record);
    final lineTotal = _getSaleLineTotal(record);
    final currency = (record['currency'] as String?) ?? 'TJS';
    final isFullReturn = qty > 0 && ret >= qty;
    final sub = _productSubline(record);

    Color? bg;
    Color? border;
    if (status == 'full') {
      bg = const Color(0xFFFF4D4F).withValues(alpha: dark ? 0.08 : 0.12);
      border = const Color(0xFFFF4D4F).withValues(alpha: 0.35);
    } else if (status == 'partial') {
      bg = const Color(0xFFFAAD14).withValues(alpha: dark ? 0.08 : 0.12);
      border = const Color(0xFFFAAD14).withValues(alpha: 0.35);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg ?? (dark ? AppBrand.darkRow : cs.surfaceContainer),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border ?? (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((record['product_name'] ?? '—').toString(), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface, height: 1.3)),
                    if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTrash) ...[
                    IconButton(tooltip: 'Восстановить', onPressed: onRestore, icon: const Icon(Icons.undo_rounded, size: 20)),
                    IconButton(
                      tooltip: 'Удалить навсегда',
                      onPressed: deleting ? null : onDelete,
                      icon: deleting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                    ),
                  ] else ...[
                    IconButton(tooltip: 'Изменить', onPressed: isFullReturn ? null : onEdit, icon: const Icon(Icons.edit_outlined, size: 20)),
                    IconButton(tooltip: isFullReturn ? 'Уже возврат' : 'Возврат', onPressed: isFullReturn ? null : onReturn, icon: const Icon(Icons.undo_rounded, size: 20)),
                    IconButton(
                      tooltip: 'Удалить',
                      onPressed: deleting ? null : onDelete,
                      icon: deleting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (status != 'none') ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 'full' ? const Color(0xFFFF4D4F).withValues(alpha: 0.15) : const Color(0xFFFAAD14).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status == 'full' ? 'Полный возврат' : 'Частичный возврат',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status == 'full' ? const Color(0xFFFF7875) : const Color(0xFFFAAD14)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.25)),
            ),
            child: Text(
              lineTotal > 0
                  ? '${formatRuMoney(lineTotal, fractionDigits: lineTotal % 1 == 0 ? 0 : 2)} $currency'
                  : '—',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF86EFAC), height: 1.25),
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.35,
            children: [
              _MetaPair(dark: dark, label: 'Дата', value: _formatSaleDateTime(record)),
              if (showStore) _MetaPair(dark: dark, label: 'Магазин', value: (record['outlet_name'] ?? '—').toString()),
              _MetaPair(
                dark: dark,
                label: 'Кол-во',
                value: ret > 0 ? '${ret.toStringAsFixed(ret % 1 == 0 ? 0 : 3)} / ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 3)} возврат' : qty.toString(),
              ),
              _MetaPair(
                dark: dark,
                label: 'Цена',
                value: record['unit_price'] != null ? '${formatRuInt((_asDouble(record['unit_price']) ?? 0).round())} $currency' : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPair extends StatelessWidget {
  const _MetaPair({required this.dark, required this.label, required this.value});
  final bool dark;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelColor = dark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B);
    final valueColor = dark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF0F172A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: labelColor, height: 1.2)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor, height: 1.25),
            ),
          ),
        ],
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
    final available = widget.products.where((p) => (_asDouble(p['quantity']) ?? 0) > 0);
    final items = available.where((p) {
      final name = (p['product_name'] ?? p['name'] ?? '').toString().toLowerCase();
      final model = (p['model'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      final s = q.trim().toLowerCase();
      if (s.isEmpty) return true;
      return name.contains(s) || model.contains(s) || sku.contains(s);
    }).take(250).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
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

String _formatSaleDateTime(Map<String, dynamic> record) {
  final created = record['created_at'];
  if (created != null) {
    final d = DateTime.tryParse(created.toString());
    if (d != null) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final min = d.minute.toString().padLeft(2, '0');
      return '$dd.$mm.${d.year} $hh:$min';
    }
  }
  final sold = record['sold_at']?.toString();
  if (sold == null || sold.isEmpty) return '—';
  final d = DateTime.tryParse(sold.length >= 10 ? sold.substring(0, 10) : sold);
  if (d == null) return sold.length >= 10 ? sold.substring(0, 10) : sold;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

String? _productSubline(Map<String, dynamic> record) {
  final parts = [
    record['model'] ?? record['product_model'],
    record['brand'] ?? record['product_brand'],
    record['color'] ?? record['product_color'],
    record['size'] ?? record['product_size'],
    record['memory'] ?? record['product_memory'],
    record['ram'] ?? record['product_ram'],
  ].where((x) => x != null && x.toString().trim().isNotEmpty).map((x) => x.toString()).toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

String _getSaleReturnStatus(Map<String, dynamic> record) {
  final qty = _asDouble(record['quantity']) ?? 0;
  final ret = _asDouble(record['total_returned']) ?? 0;
  if (qty > 0 && ret >= qty) return 'full';
  if (ret > 0) return 'partial';
  return 'none';
}

double _getSaleLineTotal(Map<String, dynamic> record) {
  final qty = _asDouble(record['quantity']) ?? 0;
  final price = _asDouble(record['unit_price']) ?? 0;
  return qty * price;
}

String _fillSmsTemplate(String key, Map<String, String> vars) {
  const templates = <String, String>{
    'nasiya_sale': 'TOJIr: покупка в насию на сумму {amount} TJS. Код подтверждения: {code}',
    'partial_sale': 'TOJIr: частичная оплата {paid} TJS, долг {debt} TJS. Код: {code}',
  };
  var t = templates[key] ?? '';
  for (final e in vars.entries) {
    t = t.replaceAll('{${e.key}}', e.value);
  }
  return t;
}

