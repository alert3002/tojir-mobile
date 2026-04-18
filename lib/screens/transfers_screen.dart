import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

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
  String? selectedProductLabel;
  Map<String, dynamic>? selectedProductSnapshot;

  final TextEditingController quantityCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();
  final TextEditingController historySearchCtrl = TextEditingController();
  String historySearch = '';
  DateTimeRange? historyDateRange;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadWarehouses();
      if (!_isSeller) fromType = 'warehouse';
      await _loadOutlets();
      if (_isSeller) await _loadSellerFromOutlets();
      await _loadProducts();
      await _loadTransfers();
    });
  }

  @override
  void dispose() {
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
        setState(() => transferRows = items);
      } else {
        setState(() => transferRows = const []);
      }
    } catch (_) {
      if (mounted) setState(() => transferRows = const []);
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Map<String, dynamic>? _selectedProductMap() {
    if (selectedProductId == null) return null;
    if (selectedProductSnapshot != null && _asInt(selectedProductSnapshot!['id']) == selectedProductId) {
      return selectedProductSnapshot;
    }
    for (final p in products) {
      if (_asInt(p['id']) == selectedProductId) return p;
    }
    return selectedProductSnapshot;
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
        selectedProductLabel = null;
        selectedProductSnapshot = null;
        quantityCtrl.clear();
        noteCtrl.clear();
        if (!_isSeller) fromOutletId = null;
      });
      if (_isSeller && sellerToOutletId != null) {
        // to_outlet остаётся тем же
      }
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
    final initial = historyDateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
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
    setState(() => historyDateRange = picked);
    await _loadTransfers();
  }

  Future<void> _openProductPicker() async {
    final wh = _effectiveWarehouse;
    if (wh == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TransferProductPickerSheet(
        warehouseId: wh,
        outletId: fromType == 'outlet' ? fromOutletId : null,
        api: context.read<ApiClient>(),
        onPick: (Map<String, dynamic> p) {
          final id = _asInt(p['id']);
          if (id == null) return;
          setState(() {
            selectedProductId = id;
            selectedProductUnit = (p['unit'] ?? 'pcs').toString();
            selectedProductLabel = _productLineLabel(p);
            selectedProductSnapshot = Map<String, dynamic>.from(p);
            quantityCtrl.clear();
          });
          Navigator.of(ctx).pop();
        },
      ),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('Перемещения', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 14),
              _TransfersCard(
                dark: dark,
                cs: cs,
                title: 'Оформить перемещение',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showWarehouseSelect) ...[
                      Text('Склад', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      InputDecorator(
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: selectedWarehouseId,
                            hint: const Text('Склад'),
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
                                selectedProductLabel = null;
                                selectedProductSnapshot = null;
                                quantityCtrl.clear();
                              });
                              await _loadProducts();
                              await _loadTransfers();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_isSeller) ...[
                      Text('Откуда', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'warehouse', label: Text('Склад')),
                          ButtonSegment(value: 'outlet', label: Text('Магазин')),
                        ],
                        selected: {fromType},
                        onSelectionChanged: (s) async {
                          setState(() {
                            fromType = s.first;
                            fromOutletId = null;
                            selectedProductId = null;
                            selectedProductLabel = null;
                            selectedProductSnapshot = null;
                            quantityCtrl.clear();
                          });
                          await _loadProducts();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (fromType == 'outlet' || _isSeller) ...[
                      Text('Из магазина', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      if (loadingSellerFrom && _isSeller)
                        Text('Загрузка…', style: TextStyle(color: cs.onSurfaceVariant))
                      else
                        InputDecorator(
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              isExpanded: true,
                              value: fromOutletId,
                              hint: const Text('Магазин'),
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
                              onChanged: (v) async {
                                setState(() {
                                  fromOutletId = v;
                                  selectedProductId = null;
                                  selectedProductLabel = null;
                                  selectedProductSnapshot = null;
                                  quantityCtrl.clear();
                                });
                                await _loadProducts();
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    Text('В магазин', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    if (_isSeller)
                      InputDecorator(
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        child: Text(
                          sellerToOutletId == null
                              ? '—'
                              : (() {
                                  for (final o in outlets) {
                                    if (_asInt(o['id']) == sellerToOutletId) {
                                      final name = (o['name'] ?? '').toString().trim();
                                      return name.isEmpty ? 'Магазин $sellerToOutletId' : name;
                                    }
                                  }
                                  return 'Магазин $sellerToOutletId';
                                })(),
                          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      InputDecorator(
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            isExpanded: true,
                            value: toOutletId,
                            hint: const Text('Магазин'),
                            items: outlets
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
                            onChanged: (v) => setState(() => toOutletId = v),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Товар', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: wh == null ? null : _openProductPicker,
                      icon: const Icon(Icons.inventory_2_outlined, size: 20),
                      label: Text(
                        selectedProductLabel ?? 'Выбрать товар',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (productsLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Количество (${_unitShort(selectedProductId != null ? unit : null)})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                    if (selectedProductId != null && avail != null)
                      Text('Остаток: $avail ${_unitShort(unit)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    if (selectedProductId != null)
                      Text(
                        'Количество в ${_unitShort(unit)} — как у товара',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      )
                    else
                      Text('Сначала выберите товар', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: quantityCtrl,
                      enabled: selectedProductId != null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixText: selectedProductId != null ? _unitShort(unit) : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(isDense: true, labelText: 'Примечание', hintText: 'Необязательно', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: submitLoading ? null : _submit,
                      child: Text(submitLoading ? 'Отправка…' : 'Оформить перемещение'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _TransfersCard(
                dark: dark,
                cs: cs,
                title: 'История перемещений',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: historySearchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Поиск по товару',
                      ),
                      onChanged: (v) => historySearch = v,
                      onSubmitted: (_) => _loadTransfers(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickHistoryRange,
                            icon: const Icon(Icons.date_range_rounded, size: 18),
                            label: Text(
                              historyDateRange == null
                                  ? 'Дата от — до'
                                  : '${_fmtYmd(historyDateRange!.start)} — ${_fmtYmd(historyDateRange!.end)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        if (historyDateRange != null)
                          IconButton(
                            tooltip: 'Сбросить даты',
                            onPressed: () async {
                              setState(() => historyDateRange = null);
                              await _loadTransfers();
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loadTransfers,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Обновить'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (loadingHistory) const SkeletonListBlock(rows: 5)
else if (transferRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _isSeller || wh != null ? 'Нет перемещений' : 'Выберите склад',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      ...transferRows.take(30).map((r) => _TransferHistoryTile(cs: cs, dark: dark, row: r)),
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
  const _TransfersCard({required this.dark, required this.cs, required this.title, required this.child});
  final bool dark;
  final ColorScheme cs;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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

class _TransferHistoryTile extends StatelessWidget {
  const _TransferHistoryTile({required this.cs, required this.dark, required this.row});
  final ColorScheme cs;
  final bool dark;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final created = (row['created_at'] ?? '').toString().replaceFirst('T', ' ');
    final short = created.length > 16 ? created.substring(0, 16) : created;
    final from = (row['from_outlet_name'] as String?)?.trim().isNotEmpty == true ? row['from_outlet_name'].toString() : 'Склад';
    final to = (row['to_outlet_name'] ?? '—').toString();
    final prod = (row['product_name'] ?? '—').toString();
    final qty = row['quantity'];
    final u = _unitShort(row['product_unit']?.toString());
    final note = (row['note'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        borderRadius: AppShape.br,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(short.isEmpty ? '—' : short, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(prod, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Откуда: $from → Куда: $to', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Text('Кол-во: ${qty != null ? '$qty $u' : '—'}', style: TextStyle(fontSize: 12, color: cs.onSurface)),
              if (note.isNotEmpty) Text('Примечание: $note', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferProductPickerSheet extends StatefulWidget {
  const _TransferProductPickerSheet({
    required this.warehouseId,
    required this.outletId,
    required this.api,
    required this.onPick,
  });

  final int warehouseId;
  final int? outletId;
  final ApiClient api;
  final void Function(Map<String, dynamic>) onPick;

  @override
  State<_TransferProductPickerSheet> createState() => _TransferProductPickerSheetState();
}

class _TransferProductPickerSheetState extends State<_TransferProductPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.addListener(_schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(''));
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(_search.text));
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final qp = <String, String>{'warehouse': widget.warehouseId.toString()};
      if (q.trim().isNotEmpty) qp['search'] = q.trim();
      if (widget.outletId != null) qp['outlet'] = widget.outletId.toString();
      final path = 'inventory/products/?${Uri(queryParameters: qp).query}';
      final res = await widget.api.get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => _items = items);
      } else {
        setState(() => _items = const []);
      }
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
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
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Поиск товара', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Название, модель, артикул…',
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _items.isEmpty && !_loading
                  ? Center(child: Text('Нет данных', style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final p = _items[i];
                        final unit = (p['unit'] ?? 'pcs').toString();
                        final ul = _unitShort(unit);
                        final isOutlet = widget.outletId != null;
                        final availRaw = isOutlet ? p['outlet_stock_quantity'] : p['quantity'];
                        final avail = _asDouble(availRaw);
                        final availText = avail != null ? 'Ост: $avail $ul' : 'Ед: $ul';
                        return ListTile(
                          title: Text(_productLineLabel(p), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(availText, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          onTap: () => widget.onPick(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
