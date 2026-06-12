import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_brand.dart';
import '../utils/permissions.dart';
import '../utils/product_scan_utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _historyPageSize = 15;

const _unitLabels = <String, String>{
  'pcs': 'шт',
  'L': 'л',
  'kg': 'кг',
  't': 'т',
  'ml': 'мл',
  'g': 'г',
  'm': 'м',
  'pack': 'упак',
  'box': 'кор',
  'bottle': 'бут',
};

class _QtyProps {
  const _QtyProps({required this.min, required this.step, required this.precision});
  final double min;
  final double step;
  final int precision;
}

_QtyProps _qtyPropsForUnit(String? unit) {
  switch (unit) {
    case 'pcs':
    case 'pack':
    case 'box':
    case 'bottle':
      return const _QtyProps(min: 1, step: 1, precision: 0);
    default:
      return const _QtyProps(min: 0.001, step: 0.001, precision: 3);
  }
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

String _fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtRuDateTime(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString().trim();
  if (s.isEmpty) return '—';
  try {
    final dt = DateTime.parse(s);
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d, $t';
  } catch (_) {
    final norm = s.replaceFirst('T', ' ');
    return norm.length > 16 ? norm.substring(0, 16) : norm;
  }
}

String _unitShort(String? u) => _unitLabels[u ?? ''] ?? u ?? 'шт';

String _productLineLabel(Map<String, dynamic> p) {
  final name = (p['name'] ?? '—').toString();
  final model = (p['model'] ?? '').toString().trim();
  final brand = (p['brand'] ?? '').toString().trim();
  final bits = <String>[name];
  if (model.isNotEmpty) bits.add(model);
  if (brand.isNotEmpty) bits.add(brand);
  return bits.join(' · ');
}

String _productOptionLabel(Map<String, dynamic> p, {required bool fromOutlet}) {
  final unit = _unitShort(p['unit']?.toString());
  final availRaw = fromOutlet ? p['outlet_stock_quantity'] : p['quantity'];
  final avail = _asDouble(availRaw);
  final availText = avail != null ? 'Ост: $avail $unit' : 'Ед: $unit';
  final label = '${_productLineLabel(p)} · $availText';
  return label.length > 170 ? label.substring(0, 170) : label;
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  List<Map<String, dynamic>> warehouses = const [];
  List<Map<String, dynamic>> outlets = const [];
  List<Map<String, dynamic>> sellerFromOutlets = const [];
  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> transferRows = const [];

  bool loadingOutlets = false;
  bool loadingSellerFrom = false;
  bool productsLoading = false;
  bool loadingHistory = false;
  bool submitLoading = false;

  int? selectedWarehouseId;
  int? sellerToOutletId;
  String fromType = 'warehouse';
  int? fromOutletId;
  int? toOutletId;
  int? selectedProductId;
  String? selectedProductUnit;

  final TextEditingController scanCtrl = TextEditingController();
  final TextEditingController productSearchCtrl = TextEditingController();
  final TextEditingController quantityCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();
  final TextEditingController historySearchCtrl = TextEditingController();

  String productSearch = '';
  String historySearch = '';
  DateTimeRange? historyDateRange;
  int historyPage = 1;

  Timer? _productSearchDebounce;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _isSeller => (_user?['role'] as String?) == 'seller';

  int? get _effectiveWarehouse {
    final u = _user;
    if (u == null) return null;
    if (_isSeller) {
      return _asInt(u['warehouse']) ?? _asInt(u['warehouse_id']);
    }
    return selectedWarehouseId ?? _asInt(u['warehouse']) ?? _asInt(u['warehouse_id']);
  }

  bool get _showWarehouseSelect {
    final u = _user;
    if (u == null || _isSeller) return false;
    final role = u['role'] as String?;
    return role == 'platform' || warehouses.length > 1;
  }

  @override
  void initState() {
    super.initState();
    if (_isSeller) fromType = 'outlet';
    productSearchCtrl.addListener(_onProductSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadWarehouses();
      await _loadOutlets();
      if (_isSeller) await _loadSellerFromOutlets();
      await _loadProducts();
      await _loadTransfers();
    });
  }

  void _onProductSearchChanged() {
    final v = productSearchCtrl.text;
    if (v == productSearch) return;
    productSearch = v;
    _productSearchDebounce?.cancel();
    _productSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadProducts();
    });
  }

  @override
  void dispose() {
    _productSearchDebounce?.cancel();
    scanCtrl.dispose();
    productSearchCtrl.dispose();
    quantityCtrl.dispose();
    noteCtrl.dispose();
    historySearchCtrl.dispose();
    super.dispose();
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

  Future<void> _loadWarehouses() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/warehouses/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => warehouses = items);
      }
    } catch (_) {
      if (mounted) setState(() => warehouses = const []);
    }
  }

  Future<void> _loadOutlets() async {
    final u = _user;
    if (u == null) return;
    setState(() => loadingOutlets = true);
    try {
      final role = u['role'] as String?;
      final wh = u['warehouse'];
      final path = role == 'seller'
          ? 'inventory/outlets'
          : 'inventory/outlets${wh != null ? '?warehouse=$wh' : ''}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          outlets = items;
          if (_isSeller && items.isNotEmpty) {
            final ok = sellerToOutletId != null && items.any((o) => _asInt(o['id']) == sellerToOutletId);
            if (!ok) sellerToOutletId = _asInt(items.first['id']);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => outlets = const []);
    } finally {
      if (mounted) setState(() => loadingOutlets = false);
    }
  }

  Future<void> _loadSellerFromOutlets() async {
    if (!_isSeller) return;
    setState(() => loadingSellerFrom = true);
    try {
      final qp = <String, String>{'exclude_my': '1'};
      if (sellerToOutletId != null) qp['exclude_outlet'] = sellerToOutletId.toString();
      final res = await context.read<ApiClient>().get('inventory/outlets?${Uri(queryParameters: qp).query}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => sellerFromOutlets = items);
      }
    } catch (_) {
      if (mounted) setState(() => sellerFromOutlets = const []);
    } finally {
      if (mounted) setState(() => loadingSellerFrom = false);
    }
  }

  Future<void> _loadProducts() async {
    final wh = _effectiveWarehouse;
    if (wh == null) {
      setState(() => products = const []);
      return;
    }
    setState(() => productsLoading = true);
    try {
      final qp = <String, String>{'warehouse': wh.toString()};
      if (productSearch.trim().isNotEmpty) qp['search'] = productSearch.trim();
      if (fromType == 'outlet' && fromOutletId != null) qp['outlet'] = fromOutletId.toString();
      final path = 'inventory/products/?${Uri(queryParameters: qp).query}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => products = items);
      } else {
        setState(() => products = const []);
      }
    } catch (_) {
      if (mounted) setState(() => products = const []);
    } finally {
      if (mounted) setState(() => productsLoading = false);
    }
  }

  Future<void> _loadTransfers() async {
    final wh = _effectiveWarehouse;
    if (wh == null) {
      setState(() => transferRows = const []);
      return;
    }
    setState(() => loadingHistory = true);
    try {
      final qp = <String, String>{'warehouse': wh.toString()};
      if (historySearch.trim().isNotEmpty) qp['search'] = historySearch.trim();
      if (historyDateRange != null) {
        qp['date_from'] = _fmtYmd(historyDateRange!.start);
        qp['date_to'] = _fmtYmd(historyDateRange!.end);
      }
      final path = 'inventory/transfers/?${Uri(queryParameters: qp).query}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          transferRows = items;
          historyPage = 1;
        });
      } else {
        setState(() => transferRows = const []);
      }
    } catch (_) {
      if (mounted) setState(() => transferRows = const []);
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Map<String, dynamic>? _findProductByCode(String raw) {
    final norm = normalizeScanCode(raw).toLowerCase();
    if (norm.isEmpty) return null;
    for (final p in products) {
      final barcode = normalizeScanCode((p['barcode'] ?? '').toString()).toLowerCase();
      final sku = normalizeScanCode((p['sku'] ?? '').toString()).toLowerCase();
      if (barcode == norm || sku == norm) return p;
    }
    for (final p in products) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      if (name.contains(norm)) return p;
    }
    return null;
  }

  void _selectProduct(Map<String, dynamic> p) {
    final id = _asInt(p['id']);
    if (id == null) return;
    setState(() {
      selectedProductId = id;
      selectedProductUnit = (p['unit'] ?? 'pcs').toString();
      quantityCtrl.clear();
    });
  }

  Future<void> _onScanProduct(String raw) async {
    final norm = normalizeScanCode(raw);
    if (norm.isEmpty) return;
    var match = _findProductByCode(norm);
    if (match == null) {
      setState(() {
        productSearch = norm;
        productSearchCtrl.text = norm;
      });
      await _loadProducts();
      match = _findProductByCode(norm);
    }
    if (match != null) {
      _selectProduct(match);
      _snack('Товар: ${match['name'] ?? '—'}');
      scanCtrl.clear();
    } else {
      _snack('Товар не найден', error: true);
    }
  }

  Map<String, dynamic>? _selectedProductMap() {
    if (selectedProductId == null) return null;
    for (final p in products) {
      if (_asInt(p['id']) == selectedProductId) return p;
    }
    return null;
  }

  double? _availableForProduct(Map<String, dynamic>? p) {
    if (p == null) return null;
    final raw = (fromType == 'outlet' && fromOutletId != null) ? p['outlet_stock_quantity'] : p['quantity'];
    return _asDouble(raw);
  }

  String _apiErr(Map<String, dynamic> err) {
    final d = err['detail'];
    if (d != null) return d.toString();
    final q = err['quantity'];
    if (q is List && q.isNotEmpty) return q.first.toString();
    final pr = err['product'];
    if (pr is List && pr.isNotEmpty) return pr.first.toString();
    return 'Ошибка';
  }

  Future<void> _submit() async {
    final wh = _effectiveWarehouse;
    if (wh == null) {
      _snack('Выберите склад', error: true);
      return;
    }
    final effFromType = _isSeller ? 'outlet' : fromType;
    final effFromOutlet = effFromType == 'outlet' ? fromOutletId : null;
    if (_isSeller && effFromType != 'outlet') {
      _snack('Продавец может перемещать только из магазина', error: true);
      return;
    }
    if (effFromType == 'outlet' && effFromOutlet == null) {
      _snack('Выберите магазин отправителя', error: true);
      return;
    }
    final toId = _isSeller ? sellerToOutletId : toOutletId;
    if (toId == null) {
      _snack(_isSeller ? 'Магазин не определён' : 'Выберите магазин', error: true);
      return;
    }
    if (selectedProductId == null) {
      _snack('Выберите товар', error: true);
      return;
    }
    final p = _selectedProductMap();
    final unit = selectedProductUnit ?? (p?['unit'] ?? 'pcs').toString();
    final props = _qtyPropsForUnit(unit);
    final qText = quantityCtrl.text.replaceAll(',', '.').trim();
    final q = double.tryParse(qText);
    if (q == null) {
      _snack('Укажите количество', error: true);
      return;
    }
    if (q < props.min) {
      _snack('Не меньше ${props.min} ${_unitShort(unit)}', error: true);
      return;
    }
    if (props.precision == 0 && q != q.roundToDouble()) {
      _snack('Укажите целое число (${_unitShort(unit)})', error: true);
      return;
    }
    final avail = _availableForProduct(p);
    if (avail != null && q > avail) {
      _snack('Нельзя больше остатка: $avail ${_unitShort(unit)}', error: true);
      return;
    }

    setState(() => submitLoading = true);
    try {
      final res = await context.read<ApiClient>().post(
            'inventory/transfers/',
            body: {
              'warehouse': wh,
              'from_outlet': effFromOutlet,
              'to_outlet': toId,
              'product': selectedProductId,
              'quantity': props.precision == 0 ? q.round() : q,
              'note': noteCtrl.text.trim(),
            },
          );
      if (!mounted) return;
      final data = res.body.isEmpty ? <String, dynamic>{} : (jsonDecode(res.body) as Map?)?.cast<String, dynamic>() ?? {};
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_apiErr(data));
      }
      _snack('Перемещение оформлено');
      setState(() {
        selectedProductId = null;
        selectedProductUnit = null;
        quantityCtrl.clear();
        noteCtrl.clear();
        if (!_isSeller) fromOutletId = null;
      });
      await _loadProducts();
      await _loadTransfers();
      if (_isSeller) await _loadSellerFromOutlets();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => submitLoading = false);
    }
  }

  Future<void> _pickHistoryRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: historyDateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() => historyDateRange = picked);
    await _loadTransfers();
  }

  InputDecoration _fieldDecoration({String? label, String? hint, bool required = false}) {
    return InputDecoration(
      isDense: true,
      labelText: required && label != null ? '$label *' : label,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'transfers', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
    }

    final wh = _effectiveWarehouse;
    final fromOutletList = _isSeller ? sellerFromOutlets : outlets;
    final p = _selectedProductMap();
    final unit = selectedProductUnit ?? (p?['unit'] ?? 'pcs').toString();
    final avail = _availableForProduct(p);
    final historySlice = transferRows.skip((historyPage - 1) * _historyPageSize).take(_historyPageSize).toList();

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadWarehouses();
            await _loadOutlets();
            if (_isSeller) await _loadSellerFromOutlets();
            await _loadProducts();
            await _loadTransfers();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            children: [
              Text('Перемещения', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.25)),
              const SizedBox(height: 10),
              _TransfersCard(
                title: 'Оформить перемещение',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showWarehouseSelect) ...[
                      Row(
                        children: [
                          Text('Склад:', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              key: ValueKey('wh-$selectedWarehouseId'),
                              initialValue: selectedWarehouseId,
                              isExpanded: true,
                              decoration: _fieldDecoration(hint: 'Склад'),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('Не выбран')),
                                ...warehouses.map((w) {
                                  final id = _asInt(w['id']);
                                  if (id == null) return null;
                                  return DropdownMenuItem<int?>(
                                    value: id,
                                    child: Text((w['name'] ?? 'Склад $id').toString()),
                                  );
                                }).whereType<DropdownMenuItem<int?>>(),
                              ],
                              onChanged: (v) async {
                                setState(() {
                                  selectedWarehouseId = v;
                                  fromOutletId = null;
                                  toOutletId = null;
                                  selectedProductId = null;
                                  selectedProductUnit = null;
                                  quantityCtrl.clear();
                                });
                                await _loadProducts();
                                await _loadTransfers();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (!_isSeller) ...[
                      Text('Откуда', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Склад', style: TextStyle(fontSize: 14)),
                              value: 'warehouse',
                              groupValue: fromType,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) async {
                                if (v == null) return;
                                setState(() {
                                  fromType = v;
                                  fromOutletId = null;
                                  selectedProductId = null;
                                  selectedProductUnit = null;
                                  quantityCtrl.clear();
                                });
                                await _loadProducts();
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Магазин', style: TextStyle(fontSize: 14)),
                              value: 'outlet',
                              groupValue: fromType,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) async {
                                if (v == null) return;
                                setState(() {
                                  fromType = v;
                                  fromOutletId = null;
                                  selectedProductId = null;
                                  selectedProductUnit = null;
                                  quantityCtrl.clear();
                                });
                                await _loadProducts();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (fromType == 'outlet' || _isSeller) ...[
                      DropdownButtonFormField<int?>(
                        key: ValueKey<String>('from-$fromOutletId'),
                        initialValue: fromOutletId,
                        isExpanded: true,
                        decoration: _fieldDecoration(label: 'Из магазина', required: true),
                        hint: loadingSellerFrom && _isSeller ? const Text('Загрузка…') : const Text('Магазин'),
                        items: fromOutletList
                            .map((o) {
                              final id = _asInt(o['id']);
                              if (id == null) return null;
                              final name = (o['name'] ?? '').toString().trim();
                              return DropdownMenuItem<int?>(
                                value: id,
                                child: Text(name.isEmpty ? 'Магазин $id' : name),
                              );
                            })
                            .whereType<DropdownMenuItem<int?>>()
                            .toList(),
                        onChanged: (loadingSellerFrom && _isSeller)
                            ? null
                            : (v) async {
                                setState(() {
                                  fromOutletId = v;
                                  selectedProductId = null;
                                  selectedProductUnit = null;
                                  quantityCtrl.clear();
                                });
                                await _loadProducts();
                              },
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<int?>(
                      key: ValueKey<String>('to-${_isSeller ? sellerToOutletId : toOutletId}'),
                      initialValue: _isSeller ? sellerToOutletId : toOutletId,
                      isExpanded: true,
                      decoration: _fieldDecoration(label: 'В магазин', required: true),
                      hint: const Text('Магазин'),
                      items: _isSeller
                          ? outlets
                              .where((o) => _asInt(o['id']) == sellerToOutletId)
                              .map((o) {
                                final id = _asInt(o['id']);
                                if (id == null) return null;
                                final name = (o['name'] ?? '').toString().trim();
                                return DropdownMenuItem<int?>(
                                  value: id,
                                  child: Text(name.isEmpty ? 'Магазин $id' : name),
                                );
                              })
                              .whereType<DropdownMenuItem<int?>>()
                              .toList()
                          : outlets
                              .map((o) {
                                final id = _asInt(o['id']);
                                if (id == null) return null;
                                final name = (o['name'] ?? '').toString().trim();
                                return DropdownMenuItem<int?>(
                                  value: id,
                                  child: Text(name.isEmpty ? 'Магазин $id' : name),
                                );
                              })
                              .whereType<DropdownMenuItem<int?>>()
                              .toList(),
                      onChanged: _isSeller ? null : (v) => setState(() => toOutletId = v),
                    ),
                    const SizedBox(height: 10),
                    Text('Сканер', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: scanCtrl,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 20),
                              hintText: 'Сканируйте штрих-код, IMEI или артикул',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onSubmitted: _onScanProduct,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton(
                            onPressed: () => _onScanProduct(scanCtrl.text),
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Icon(Icons.center_focus_weak_rounded, size: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Товар', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: productSearchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Поиск товара',
                        suffixIcon: productsLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.search_rounded, size: 20),
                                onPressed: _loadProducts,
                              ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (_) => _loadProducts(),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      key: ValueKey('prod-$selectedProductId-${products.length}'),
                      initialValue: selectedProductId,
                      isExpanded: true,
                      decoration: _fieldDecoration(required: true),
                      hint: Text(productsLoading ? 'Загрузка…' : 'Поиск товара'),
                      items: products
                          .map((pr) {
                            final id = _asInt(pr['id']);
                            if (id == null) return null;
                            return DropdownMenuItem<int?>(
                              value: id,
                              child: Text(
                                _productOptionLabel(pr, fromOutlet: fromType == 'outlet' && fromOutletId != null),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          })
                          .whereType<DropdownMenuItem<int?>>()
                          .toList(),
                      onChanged: productsLoading
                          ? null
                          : (v) {
                              if (v == null) {
                                setState(() {
                                  selectedProductId = null;
                                  selectedProductUnit = null;
                                  quantityCtrl.clear();
                                });
                                return;
                              }
                              final pr = products.cast<Map<String, dynamic>?>().firstWhere(
                                    (x) => _asInt(x?['id']) == v,
                                    orElse: () => null,
                                  );
                              if (pr != null) _selectProduct(pr);
                            },
                    ),
                    const SizedBox(height: 10),
                    Text('Количество', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text(
                      selectedProductId != null ? 'В ${_unitShort(unit)}' : 'Сначала выберите товар',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: quantityCtrl,
                      enabled: selectedProductId != null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: selectedProductId != null ? null : 'Выберите товар',
                        suffixText: selectedProductId != null ? _unitShort(unit) : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    if (selectedProductId != null && avail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Остаток: $avail ${_unitShort(unit)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: _fieldDecoration(label: 'Примечание', hint: 'Необязательно'),
                      minLines: 1,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: submitLoading ? null : _submit,
                        child: Text(submitLoading ? 'Отправка…' : 'Оформить перемещение', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _TransfersCard(
                title: 'История перемещений',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: historySearchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Поиск по товару',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded, size: 20),
                          onPressed: () {
                            historySearch = historySearchCtrl.text;
                            _loadTransfers();
                          },
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (v) => historySearch = v,
                      onSubmitted: (_) {
                        historySearch = historySearchCtrl.text;
                        _loadTransfers();
                      },
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _pickHistoryRange,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  historyDateRange != null ? _fmtYmd(historyDateRange!.start) : 'Дата от',
                                  style: TextStyle(fontSize: 13, color: historyDateRange != null ? cs.onSurface : cs.onSurfaceVariant),
                                ),
                              ),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: cs.onSurfaceVariant),
                              Expanded(
                                child: Text(
                                  historyDateRange != null ? _fmtYmd(historyDateRange!.end) : 'Дата до',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(fontSize: 13, color: historyDateRange != null ? cs.onSurface : cs.onSurfaceVariant),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (historyDateRange != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            setState(() => historyDateRange = null);
                            await _loadTransfers();
                          },
                          child: const Text('Сбросить даты'),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (loadingHistory)
                      const SkeletonListBlock(rows: 4)
                    else if (transferRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _isSeller || wh != null ? 'Нет перемещений' : 'Выберите склад',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      )
                    else ...[
                      for (final r in historySlice) _TransferHistoryTile(cs: cs, dark: dark, row: r),
                      if (transferRows.length > _historyPageSize)
                        _Pager(
                          page: historyPage,
                          total: (transferRows.length / _historyPageSize).ceil(),
                          onPrev: historyPage > 1 ? () => setState(() => historyPage--) : null,
                          onNext: historyPage * _historyPageSize < transferRows.length ? () => setState(() => historyPage++) : null,
                        ),
                    ],
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

class _TransfersCard extends StatelessWidget {
  const _TransfersCard({required this.title, required this.child});
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
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25))),
            ),
            child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: child),
        ],
      ),
    );
  }
}

class _TransferHistoryTile extends StatelessWidget {
  const _TransferHistoryTile({required this.cs, required this.dark, required this.row});
  final ColorScheme cs;
  final bool dark;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final from = (row['from_outlet_name'] as String?)?.trim().isNotEmpty == true ? row['from_outlet_name'].toString() : 'Склад';
    final to = (row['to_outlet_name'] ?? '—').toString();
    final prod = (row['product_name'] ?? '—').toString();
    final qty = row['quantity'];
    final u = _unitShort(row['product_unit']?.toString());
    final qtyStr = qty != null ? '${qty is num ? qty : qty.toString()} $u' : '—';
    final note = (row['note'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? AppBrand.darkRow : cs.surfaceContainer,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prod, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(_fmtRuDateTime(row['created_at']), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text('$from → $to', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text('кол-во: $qtyStr', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (note.isNotEmpty) Text(note, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.total, required this.onPrev, required this.onNext});
  final int page;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(visualDensity: VisualDensity.compact, onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, size: 20)),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppBrand.primaryBlue, borderRadius: BorderRadius.circular(999)),
            child: Text('$page', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          IconButton(visualDensity: VisualDensity.compact, onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded, size: 20)),
        ],
      ),
    );
  }
}
