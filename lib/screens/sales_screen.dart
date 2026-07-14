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
import '../utils/tj_phone.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/quick_date_range_chips.dart';

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
  String? historyPreset = 'month';
  int? filterOutletId;
  bool showTrash = false;
  List<Map<String, dynamic>> sales = const [];

  String mobileViewTab = 'sale';
  int historyMobilePage = 1;
  final Set<String> expandedReceiptKeys = <String>{};
  final _saleScanCtrl = TextEditingController();
  final _historySearchCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();
  final _productSearchFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final _checkoutKey = GlobalKey();
  String checkoutCurrency = 'TJS';
  int? deletingId;

  String productQuery = '';
  bool productBrowseOpen = false;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  List<Map<String, dynamic>> get _availableOutletProducts =>
      outletProducts.where((p) => (_asDouble(p['quantity']) ?? 0) > 0).toList();

  List<Map<String, dynamic>> get _browseProducts {
    final s = productQuery.trim().toLowerCase();
    final available = _availableOutletProducts;
    final filtered = s.isEmpty
        ? available
        : available.where((p) {
            bool hit(dynamic v) => (v ?? '').toString().toLowerCase().contains(s);
            return hit(p['product_name']) ||
                hit(p['name']) ||
                hit(p['model']) ||
                hit(p['product_model']) ||
                hit(p['brand']) ||
                hit(p['product_brand']) ||
                hit(p['sku']) ||
                hit(p['product_sku']) ||
                hit(p['barcode']) ||
                hit(p['imei']);
          }).toList();
    if (filtered.length <= 250) return filtered;
    return filtered.sublist(0, 250);
  }

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
    _productSearchFocus.addListener(_onProductSearchFocus);
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
      if (historyRange == null) {
        setState(() {
          historyPreset = 'month';
          historyRange = _historyRangeForPreset('month');
        });
      }
      await _loadRate();
      await _loadOutlets();
      await _loadHistory();
    });
  }

  void _onProductSearchFocus() {
    if (_productSearchFocus.hasFocus) {
      if (!productBrowseOpen) setState(() => productBrowseOpen = true);
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || _productSearchFocus.hasFocus) return;
      if (productBrowseOpen) setState(() => productBrowseOpen = false);
    });
  }

  void _resetProductBrowse() {
    productQuery = '';
    productBrowseOpen = false;
    _productSearchCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _productSearchFocus.unfocus();
    });
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    _productSearchFocus.removeListener(_onProductSearchFocus);
    _productSearchFocus.dispose();
    _productSearchCtrl.dispose();
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

  String? _apiDetail(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        final d = m['detail'];
        if (d is String && d.trim().isNotEmpty) return d.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadOutlets() async {
    final u = _user;
    if (u == null) return;
    setState(() => loadingOutlets = true);
    try {
      final api = context.read<ApiClient>();
      final wh = u['warehouse'];
      final path = wh != null ? 'inventory/outlets/?warehouse=$wh' : 'inventory/outlets/';
      final res = await api.get(path);
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
      } else {
        setState(() => outlets = const []);
        final msg = _apiDetail(res.body);
        if (msg != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  bool get phoneOk => !needsContact || TjPhone.isValidMobile(buyerPhone9);
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
    if (!TjPhone.isValidMobile(digits)) {
      _snack(TjPhone.validationHint(), error: true);
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

  DateTimeRange _historyRangeForPreset(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'today':
        return DateTimeRange(start: today, end: today);
      case 'week':
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case 'month':
      default:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    }
  }

  void _applyHistoryPreset(String key) {
    setState(() {
      historyPreset = key;
      historyRange = _historyRangeForPreset(key);
      historyMobilePage = 1;
    });
    _loadHistory();
  }

  Future<void> _pickHistoryDateRange() async {
    final now = DateTime.now();
    final initial = historyRange ?? _historyRangeForPreset('month');
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
      historyPreset = 'custom';
      historyRange = picked;
    });
    await _loadHistory();
  }

  Future<void> _openScanCodeDialog() async {
    final ctrl = TextEditingController(text: _saleScanCtrl.text);
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сканер'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'QR, штрих-код, IMEI'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-./:?=&%+\s]'))],
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Найти')),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || !mounted) return;
    _saleScanCtrl.text = code;
    _handleSaleScan(code);
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
      productBrowseOpen = true;
    });
    // Keep search focused so the product list stays open (like web).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _productSearchFocus.requestFocus();
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
    final historyReceipts = _groupSalesIntoReceipts(sales);
    final historyTotalPages = historyReceipts.isEmpty ? 1 : (historyReceipts.length / _salesMobilePageSize).ceil();
    final historySlice = historyReceipts.skip((historyMobilePage - 1) * _salesMobilePageSize).take(_salesMobilePageSize).toList();

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
                  Text('Продажа', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.2)),
                  const SizedBox(height: 4),
                  _SalesMobileTabs(
                    active: mobileViewTab,
                    cartCount: selectedProductIds.length,
                    historyCount: historyReceipts.length,
                    onSale: () => setState(() => mobileViewTab = 'sale'),
                    onHistory: () => setState(() => mobileViewTab = 'history'),
                  ),
                  const SizedBox(height: 10),
                  if (mobileViewTab == 'sale') ...[
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (u['role'] == 'seller' && !showStore) ...[
                            _SellerContextBanner(name: _saleOutletName()),
                            const SizedBox(height: 10),
                          ],
                          if (showStore) ...[
                            Text('Магазин', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            _OutletDropdown(
                              outlets: outlets,
                              value: saleOutletId,
                              loading: loadingOutlets,
                              allowClear: !(u['role'] == 'seller' && outlets.length <= 1),
                              onChanged: (id) async {
                                setState(() {
                                  saleOutletId = id;
                                  selectedProductIds.clear();
                                  edits.clear();
                                  _resetProductBrowse();
                                });
                                if (id != null) await _loadOutletProducts(id);
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (saleOutletId == null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('Выберите магазин', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                            )
                          else ...[
                            _SalesFindBar(
                              controller: _productSearchCtrl,
                              focusNode: _productSearchFocus,
                              loading: loadingProducts,
                              onChanged: (v) => setState(() {
                                productQuery = v;
                                productBrowseOpen = true;
                              }),
                              onClear: () => setState(() {
                                productQuery = '';
                                _productSearchCtrl.clear();
                                productBrowseOpen = true;
                              }),
                              onScanTap: _openScanCodeDialog,
                            ),
                            if (selectedProductIds.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'В ЧЕКЕ',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
                                ),
                              ),
                              const SizedBox(height: 8),
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
                            ],
                            if (productBrowseOpen) ...[
                              const SizedBox(height: 10),
                              _SalesProductPanel(
                                loading: loadingProducts,
                                query: productQuery,
                                items: _browseProducts,
                                availableCount: _availableOutletProducts.length,
                                selectedIds: selectedProductIds,
                                onPick: _addProduct,
                              ),
                            ] else if (selectedProductIds.isEmpty) ...[
                              const SizedBox(height: 4),
                              _SalesEmptyHint(
                                loading: loadingOutlets || loadingProducts,
                                noOutlet: saleOutletId == null,
                                hasProducts: _availableOutletProducts.isNotEmpty,
                              ),
                            ],
                            if (selectedProductIds.isNotEmpty) ...[
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
                    _SectionCard(
                      child: Column(
                        children: [
                          _SalesHistoryFilters(
                            cs: cs,
                            dark: dark,
                            searchCtrl: _historySearchCtrl,
                            onSearch: (v) {
                              historySearch = v;
                              setState(() => historyMobilePage = 1);
                            },
                            onFind: () {
                              historySearch = _historySearchCtrl.text;
                              setState(() => historyMobilePage = 1);
                              _loadHistory();
                            },
                            onRefresh: _loadHistory,
                            onApply: () {
                              historySearch = _historySearchCtrl.text;
                              setState(() => historyMobilePage = 1);
                              _loadHistory();
                            },
                            preset: historyPreset,
                            onPreset: _applyHistoryPreset,
                            range: historyRange,
                            onPickRange: _pickHistoryDateRange,
                            showStore: showStore,
                            outlets: outlets,
                            outletId: filterOutletId,
                            allowOutletClear: !(u['role'] == 'seller' && outlets.length <= 1),
                            onOutletChanged: (id) => setState(() => filterOutletId = id),
                            showTrash: showTrash,
                            onTrashChanged: (v) => setState(() => showTrash = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (loadingHistory && sales.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
                      )
                    else
                      _SaleHistoryReceiptList(
                        dark: dark,
                        cs: cs,
                        receipts: historySlice,
                        expandedKeys: expandedReceiptKeys,
                        showStore: showStore,
                        showTrash: showTrash,
                        deletingId: deletingId,
                        onToggle: (key) => setState(() {
                          if (expandedReceiptKeys.contains(key)) {
                            expandedReceiptKeys.remove(key);
                          } else {
                            expandedReceiptKeys.add(key);
                          }
                        }),
                        onEdit: _openEditSale,
                        onReturn: _openReturnSale,
                        onDelete: _onDeleteSale,
                        onRestore: _restoreSale,
                      ),
                    if (!loadingHistory && historyReceipts.length > _salesMobilePageSize) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: historyMobilePage > 1 ? () => setState(() => historyMobilePage--) : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text('$historyMobilePage / $historyTotalPages'),
                          IconButton(
                            onPressed: historyMobilePage < historyTotalPages
                                ? () => setState(() => historyMobilePage++)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: AppBrand.cardDecoration(context),
      child: child,
    );
  }
}

class _SalesFindBar extends StatelessWidget {
  const _SalesFindBar({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onChanged,
    required this.onClear,
    required this.onScanTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onScanTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.32)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2563EB).withValues(alpha: 0.16),
            (dark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: dark ? 0.55 : 0.9),
          ],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !loading,
                onChanged: onChanged,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                cursorColor: const Color(0xFF60A5FA),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: dark ? const Color(0xFFBFDBFE) : AppBrand.primaryBlue),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  hintText: loading ? 'Загрузка…' : 'Найти товар',
                  hintStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: muted),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          onPressed: onClear,
                          icon: Icon(Icons.close_rounded, size: 18, color: muted),
                        ),
                ),
              ),
            ),
          ),
          Container(width: 1, height: double.infinity, color: const Color(0xFF60A5FA).withValues(alpha: 0.28)),
          Material(
            color: const Color(0xFF2563EB).withValues(alpha: 0.35),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(15)),
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(15)),
              onTap: onScanTap,
              child: const SizedBox(
                width: 64,
                height: 52,
                child: Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesProductPanel extends StatelessWidget {
  const _SalesProductPanel({
    required this.loading,
    required this.query,
    required this.items,
    required this.availableCount,
    required this.selectedIds,
    required this.onPick,
  });

  final bool loading;
  final String query;
  final List<Map<String, dynamic>> items;
  final int availableCount;
  final Set<int> selectedIds;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = query.trim().isEmpty ? 'Товары' : 'Найдено';
    final count = items.isEmpty ? '' : ' · ${items.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label$count'.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: cs.onSurfaceVariant.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 8),
        if (loading && items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))),
          )
        else if (items.isEmpty)
          _SalesEmptyHint(
            loading: false,
            noOutlet: false,
            hasProducts: availableCount > 0,
            emptySearch: availableCount > 0,
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _SalesProductRow(
                  product: items[i],
                  inCart: selectedIds.contains(_asInt(items[i]['product_id'])),
                  onPick: onPick,
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _SalesProductRow extends StatelessWidget {
  const _SalesProductRow({
    required this.product,
    required this.inCart,
    required this.onPick,
  });

  final Map<String, dynamic> product;
  final bool inCart;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final pid = _asInt(product['product_id']);
    final name = (product['product_name'] ?? product['name'] ?? '—').toString();
    final sub = _productSubline(product);
    final price = _asDouble(product['sale_price']) ?? 0;
    final qty = _asDouble(product['quantity']) ?? 0;
    final border = inCart
        ? const Color(0xFF22C55E).withValues(alpha: 0.35)
        : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08));
    final bg = inCart
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF22C55E).withValues(alpha: 0.1),
              dark ? const Color(0xFF0F172A).withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.7),
            ],
          )
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: pid == null ? null : () => onPick(pid),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
            gradient: bg,
            color: bg == null ? (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02)) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface, height: 1.25)),
                      if (sub != null) ...[
                        const SizedBox(height: 2),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            formatRuMoney(price, suffix: 'смн'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'ост. ${qty == qty.roundToDouble() ? qty.toInt() : qty}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: inCart ? const Color(0xFF22C55E).withValues(alpha: 0.9) : const Color(0xFF2563EB).withValues(alpha: 0.85),
                  ),
                  child: Icon(inCart ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
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

class _SalesMobileTabs extends StatelessWidget {
  const _SalesMobileTabs({
    required this.active,
    required this.cartCount,
    required this.historyCount,
    required this.onSale,
    required this.onHistory,
  });

  final String active;
  final int cartCount;
  final int historyCount;
  final VoidCallback onSale;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tab(String id, String label, VoidCallback onTap) {
      final selected = active == id;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 20, top: 8, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppBrand.primaryBlue : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 2.5,
                width: 56,
                decoration: BoxDecoration(
                  color: selected ? AppBrand.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final saleLabel = cartCount > 0 ? 'Товары ($cartCount)' : 'Товары';
    final historyLabel = historyCount > 0 ? 'История ($historyCount)' : 'История';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            tab('sale', saleLabel, onSale),
            tab('history', historyLabel, onHistory),
          ],
        ),
        Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
      ],
    );
  }
}

class _SalesHistoryFilters extends StatelessWidget {
  const _SalesHistoryFilters({
    required this.cs,
    required this.dark,
    required this.searchCtrl,
    required this.onSearch,
    required this.onFind,
    required this.onRefresh,
    required this.onApply,
    required this.preset,
    required this.onPreset,
    required this.range,
    required this.onPickRange,
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
  final VoidCallback onFind;
  final Future<void> Function() onRefresh;
  final VoidCallback onApply;
  final String? preset;
  final ValueChanged<String> onPreset;
  final DateTimeRange? range;
  final VoidCallback onPickRange;
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Поиск по товару',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: onSearch,
                onSubmitted: (_) => onFind(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onFind,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Найти'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Обновить'),
          ),
        ),
        const SizedBox(height: 10),
        QuickDateRangeChips(
          colorScheme: cs,
          selected: preset == 'custom' ? null : preset,
          showPeriod: false,
          onToday: () => onPreset('today'),
          onWeek: () => onPreset('week'),
          onMonth: () => onPreset('month'),
          onPeriod: onPickRange,
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPickRange,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fieldBorder),
                color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      range != null ? '${_fmtYmd(range!.start)} → ${_fmtYmd(range!.end)}' : 'Начальная дата → Конечная дата',
                      style: TextStyle(fontSize: 13, color: range != null ? cs.onSurface : cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (showStore) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey<int?>(outletId),
            initialValue: outletId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Все магазины',
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onApply,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Применить фильтры', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
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
  const _SalesEmptyHint({
    required this.loading,
    required this.noOutlet,
    required this.hasProducts,
    this.emptySearch = false,
  });

  final bool loading;
  final bool noOutlet;
  final bool hasProducts;
  final bool emptySearch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final String title;
    final String? sub;
    if (loading) {
      title = 'Загрузка…';
      sub = null;
    } else if (noOutlet) {
      title = 'Выберите магазин';
      sub = null;
    } else if (emptySearch) {
      title = 'Ничего не найдено';
      sub = 'Попробуйте другое название или камеру';
    } else if (hasProducts) {
      title = 'Корзина пуста';
      sub = 'Нажмите поиск или камеру';
    } else {
      title = 'Нет товаров';
      sub = 'В этом магазине нет товаров в наличии';
    }

    return CustomPaint(
      painter: _DashedRRectPainter(
        color: dark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.14),
        radius: 12,
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 28, color: AppBrand.primaryBlue.withValues(alpha: 0.8)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
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
                    errorText: needsContact && buyerPhone9.isNotEmpty && !TjPhone.isValidMobile(buyerPhone9)
                        ? TjPhone.validationHint()
                        : null,
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

class _SaleHistoryReceiptList extends StatelessWidget {
  const _SaleHistoryReceiptList({
    required this.dark,
    required this.cs,
    required this.receipts,
    required this.expandedKeys,
    required this.showStore,
    required this.showTrash,
    required this.deletingId,
    required this.onToggle,
    required this.onEdit,
    required this.onReturn,
    required this.onDelete,
    required this.onRestore,
  });

  final bool dark;
  final ColorScheme cs;
  final List<_SaleReceipt> receipts;
  final Set<String> expandedKeys;
  final bool showStore;
  final bool showTrash;
  final int? deletingId;
  final ValueChanged<String> onToggle;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onReturn;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final ValueChanged<Map<String, dynamic>> onRestore;

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Text('Нет продаж', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return Column(
      children: [
        for (final receipt in receipts)
          _SaleHistoryReceiptCard(
            dark: dark,
            cs: cs,
            receipt: receipt,
            expanded: expandedKeys.contains(receipt.key),
            showStore: showStore,
            showTrash: showTrash,
            deletingId: deletingId,
            onToggle: () => onToggle(receipt.key),
            onEdit: onEdit,
            onReturn: onReturn,
            onDelete: onDelete,
            onRestore: onRestore,
          ),
      ],
    );
  }
}

class _SaleHistoryReceiptCard extends StatelessWidget {
  const _SaleHistoryReceiptCard({
    required this.dark,
    required this.cs,
    required this.receipt,
    required this.expanded,
    required this.showStore,
    required this.showTrash,
    required this.deletingId,
    required this.onToggle,
    required this.onEdit,
    required this.onReturn,
    required this.onDelete,
    required this.onRestore,
  });

  final bool dark;
  final ColorScheme cs;
  final _SaleReceipt receipt;
  final bool expanded;
  final bool showStore;
  final bool showTrash;
  final int? deletingId;
  final VoidCallback onToggle;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onReturn;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final ValueChanged<Map<String, dynamic>> onRestore;

  @override
  Widget build(BuildContext context) {
    final multi = receipt.count > 1;
    final border = expanded
        ? const Color(0xFF22C55E).withValues(alpha: 0.35)
        : multi
            ? const Color(0xFF60A5FA).withValues(alpha: 0.28)
            : (dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: dark ? AppBrand.darkCard : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            multi ? 'Чек · ${receipt.count} товара' : receipt.title,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface, height: 1.25),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              receipt.datetime,
                              if (showStore) receipt.outletName,
                              receipt.payment,
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          if (!expanded && multi) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                ...receipt.items.take(3).map((it) => (it['product_name'] ?? 'Товар').toString()),
                                if (receipt.count > 3) '+${receipt.count - 3}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: const Color(0xFF93C5FD).withValues(alpha: 0.9)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          receipt.total > 0 ? '${formatRuMoney(receipt.total)} смн' : '—',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF86EFAC), height: 1.2),
                        ),
                        const SizedBox(height: 6),
                        Icon(
                          expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (var i = 0; i < receipt.items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _SaleHistoryLineCard(
                      dark: dark,
                      cs: cs,
                      record: receipt.items[i],
                      showTrash: showTrash,
                      deleting: deletingId == _asInt(receipt.items[i]['id']),
                      onEdit: () => onEdit(receipt.items[i]),
                      onReturn: () => onReturn(receipt.items[i]),
                      onDelete: () => onDelete(receipt.items[i]),
                      onRestore: () => onRestore(receipt.items[i]),
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

class _SaleHistoryLineCard extends StatelessWidget {
  const _SaleHistoryLineCard({
    required this.dark,
    required this.cs,
    required this.record,
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
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: bg ?? (dark ? const Color(0xFF0F172A).withValues(alpha: 0.55) : cs.surfaceContainerHighest),
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
                    Text(
                      (record['product_name'] ?? '—').toString(),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface, height: 1.25),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTrash) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Восстановить',
                      onPressed: onRestore,
                      icon: const Icon(Icons.undo_rounded, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Удалить навсегда',
                      onPressed: deleting ? null : onDelete,
                      icon: deleting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                    ),
                  ] else ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Изменить',
                      onPressed: isFullReturn ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: isFullReturn ? 'Уже возврат' : 'Возврат',
                      onPressed: isFullReturn ? null : onReturn,
                      icon: const Icon(Icons.undo_rounded, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.25)),
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
            ),
            child: Text(
              lineTotal > 0 ? '${formatRuMoney(lineTotal)} смн' : '—',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF86EFAC)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetaPair(
                  dark: dark,
                  label: 'Кол-во',
                  value: ret > 0
                      ? '${_fmtQty(ret)} / ${_fmtQty(qty)} возврат'
                      : _fmtQty(qty),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetaPair(
                  dark: dark,
                  label: 'Цена',
                  value: record['unit_price'] != null
                      ? '${formatRuMoney(_asDouble(record['unit_price']) ?? 0)} смн'
                      : '—',
                ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: labelColor, height: 1.2)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _SaleReceipt {
  const _SaleReceipt({
    required this.key,
    required this.items,
    required this.total,
    required this.title,
    required this.count,
    required this.datetime,
    required this.payment,
    required this.outletName,
  });

  final String key;
  final List<Map<String, dynamic>> items;
  final double total;
  final String title;
  final int count;
  final String datetime;
  final String payment;
  final String outletName;
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
  final ret = _asDouble(record['total_returned']) ?? 0;
  final price = _asDouble(record['unit_price']) ?? 0;
  final remain = qty - ret;
  if (remain <= 0) return 0;
  return (remain * price * 100).round() / 100;
}

String _fmtQty(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _paymentLabel(String? method) {
  switch (method) {
    case 'card':
      return 'Карта';
    case 'nasiya':
      return 'Насия';
    case 'partial':
      return 'Частично';
    default:
      return 'Наличные';
  }
}

String _receiptGroupKey(Map<String, dynamic> record) {
  final batch = (record['checkout_batch_id'] ?? '').toString().trim();
  if (batch.isNotEmpty) return 'b:$batch';
  final createdRaw = record['created_at'];
  String created;
  if (createdRaw != null) {
    final d = DateTime.tryParse(createdRaw.toString());
    if (d != null) {
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      created = '$y-$m-$day $hh:$mm';
    } else {
      created = createdRaw.toString();
    }
  } else {
    final sold = (record['sold_at'] ?? '').toString();
    created = sold.length >= 10 ? sold.substring(0, 10) : sold;
  }
  return [
    'f',
    created,
    record['outlet'] ?? record['outlet_id'] ?? '',
    record['payment_method'] ?? 'cash',
    record['buyer_phone'] ?? '',
    record['created_by'] ?? '',
  ].join('|');
}

List<_SaleReceipt> _groupSalesIntoReceipts(List<Map<String, dynamic>> rows) {
  final map = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final key = _receiptGroupKey(r);
    map.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(r);
  }
  return map.entries.map((e) {
    final sorted = [...e.value]..sort((a, b) => (_asInt(a['id']) ?? 0).compareTo(_asInt(b['id']) ?? 0));
    final first = sorted.first;
    final total = sorted.fold<double>(0, (sum, it) => sum + _getSaleLineTotal(it));
    final names = sorted.map((it) => (it['product_name'] ?? 'Товар').toString()).where((n) => n.isNotEmpty).toList();
    final title = names.length <= 2
        ? names.join(', ')
        : '${names.first} и ещё ${names.length - 1}';
    return _SaleReceipt(
      key: e.key,
      items: sorted,
      total: (total * 100).round() / 100,
      title: title.isEmpty ? 'Товар' : title,
      count: sorted.length,
      datetime: _formatSaleDateTime(first),
      payment: _paymentLabel(first['payment_method']?.toString()),
      outletName: (first['outlet_name'] ?? '—').toString(),
    );
  }).toList();
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

