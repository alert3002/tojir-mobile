import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _storesMobilePageSize = 15;
const _storesBlockBgStart = Color(0xFF1E2D47);
const _storesBlockBgEnd = Color(0xFF172033);
const _qtyBlue = Color(0xFF93C5FD);
const _qtyZero = Color(0xFFFDBA74);
const _priceGreen = Color(0xFF86EFAC);
const _blue = Color(0xFF2563EB);
const _contextBlue = Color(0xFFBFDBFE);

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

String _firstApiError(Map<String, dynamic> m) {
  final d = m['detail'];
  if (d is String && d.isNotEmpty) return d;
  for (final key in ['name', 'quantity', 'outlet', 'product']) {
    final v = m[key];
    if (v is List && v.isNotEmpty) return v.first.toString();
  }
  return 'Ошибка';
}

String? _productSubline(Map<String, dynamic> r) {
  final parts = <String>[];
  for (final k in ['model', 'brand', 'color', 'size', 'memory', 'ram']) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) parts.add(v);
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

String _unitLabel(String? u) => _unitLabels[(u ?? '').trim()] ?? (u ?? 'pcs');

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  List<Map<String, dynamic>> outlets = const [];
  List<Map<String, dynamic>> warehouses = const [];
  List<Map<String, dynamic>> products = const [];

  bool loading = false;
  bool showTrash = false;
  bool deleteOutletLoading = false;

  String? selectedOutletKey; // 'all' or outlet id string
  int mobilePage = 1;

  double usdToTjs = 11.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      await _loadWarehouses();
      await _loadOutlets();
      _ensureDefaultOutlet();
      await _loadProducts();
    });
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  void _ensureDefaultOutlet() {
    if (outlets.isEmpty) return;
    final cur = selectedOutletKey;
    final hasCur = cur != null &&
        (cur == 'all' || outlets.any((o) => _asInt(o['id'])?.toString() == cur));
    if (!hasCur) setState(() => selectedOutletKey = 'all');
  }

  Future<void> _loadRate() async {
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode != 200) return;
      final d = _tryJsonMap(res.body);
      final v = _asDouble(d['usd_to_tjs']);
      if (v != null && v.isFinite && v > 0) setState(() => usdToTjs = v);
    } catch (_) {}
  }

  Future<void> _loadWarehouses() async {
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/warehouses/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => warehouses = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List
          ? j.cast<Map<String, dynamic>>()
          : (j is Map && j['results'] is List)
              ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
              : <Map<String, dynamic>>[];
      setState(() => warehouses = list);
    } catch (_) {
      if (mounted) setState(() => warehouses = const []);
    }
  }

  Future<void> _loadOutlets() async {
    final u = _user;
    if (u == null) {
      setState(() => outlets = const []);
      return;
    }
    final api = context.read<ApiClient>();
    try {
      final wh = u['warehouse'];
      final wid = _asInt(wh);
      final isPlatform = (u['role'] as String?) == 'platform';
      final path = (wid != null && !isPlatform) ? 'inventory/outlets?warehouse=$wid' : 'inventory/outlets';
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла или вход недействителен. Войдите снова.');
        setState(() => outlets = const []);
        return;
      }
      if (res.statusCode != 200) {
        setState(() => outlets = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List
          ? j.cast<Map<String, dynamic>>()
          : (j is Map && j['results'] is List)
              ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
              : <Map<String, dynamic>>[];
      setState(() => outlets = list);
    } catch (_) {
      if (mounted) setState(() => outlets = const []);
    }
  }

  bool get _showAllOutlets => selectedOutletKey == 'all';

  int? get _subscriptionMaxStores {
    final v = _user?['subscription_max_stores'];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  List<int> get _relevantWarehouseIds {
    final wid = _asInt(_user?['warehouse']);
    if (wid != null) return [wid];
    final fromWh = warehouses.map((w) => _asInt(w['id'])).whereType<int>().toList();
    if (fromWh.isNotEmpty) return fromWh;
    return outlets.map((o) => _asInt(o['warehouse'])).whereType<int>().toSet().toList();
  }

  int _outletCountForWarehouse(int warehouseId) =>
      outlets.where((o) => _asInt(o['warehouse']) == warehouseId).length;

  bool get _storeLimitReached {
    final maxS = _subscriptionMaxStores;
    if (maxS == null) return false;
    if (maxS <= 0) return true;
    final ids = _relevantWarehouseIds;
    if (ids.isEmpty) return false;
    return ids.every((whId) => _outletCountForWarehouse(whId) >= maxS);
  }

  bool get _canManageOutlets {
    final u = _user;
    if (u == null) return false;
    if (u['role'] != 'seller') return true;
    final perms = u['allowed_perms'];
    if (perms is Map) {
      final stores = perms['stores'];
      if (stores is Map) return stores['edit'] == true || stores['delete'] == true;
    }
    return false;
  }

  Map<String, dynamic>? get _selectedOutletRecord {
    if (_showAllOutlets || selectedOutletKey == null) return null;
    final oid = int.tryParse(selectedOutletKey!);
    if (oid == null) return null;
    for (final o in outlets) {
      if (_asInt(o['id']) == oid) return o;
    }
    return null;
  }

  String? get _selectedOutletLabel {
    if (selectedOutletKey == 'all') return 'Все магазины';
    final rec = _selectedOutletRecord;
    if (rec != null) return (rec['name'] ?? 'Магазин').toString();
    return null;
  }

  List<Map<String, dynamic>> get _mobileSlice {
    final start = (mobilePage - 1) * _storesMobilePageSize;
    if (start >= products.length) return const [];
    final end = (start + _storesMobilePageSize).clamp(0, products.length);
    return products.sublist(start, end);
  }

  Future<void> _loadProducts() async {
    final key = selectedOutletKey;
    if (key == null) {
      setState(() => products = const []);
      return;
    }
    if (_showAllOutlets && outlets.isEmpty) {
      setState(() => products = const []);
      return;
    }

    setState(() => loading = true);
    final api = context.read<ApiClient>();
    try {
      if (_showAllOutlets) {
        final futures = outlets.map((o) async {
          final oid = _asInt(o['id']);
          if (oid == null) return <Map<String, dynamic>>[];
          final name = (o['name'] ?? 'Магазин $oid').toString();
          final res = await api.get('inventory/outlets/$oid/products${showTrash ? '?trash=1' : ''}');
          if (res.statusCode != 200) return <Map<String, dynamic>>[];
          final j = jsonDecode(res.body);
          final list = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
          return list
              .map((row) => <String, dynamic>{...row, 'outlet_id': oid, 'outlet_name': name})
              .toList();
        }).toList();
        final arrays = await Future.wait(futures);
        if (!mounted) return;
        setState(() {
          products = arrays.expand((x) => x).toList();
          mobilePage = 1;
        });
      } else {
        final oid = int.tryParse(key);
        if (oid == null) {
          setState(() => products = const []);
        } else {
          final res = await api.get('inventory/outlets/$oid/products${showTrash ? '?trash=1' : ''}');
          if (!mounted) return;
          if (res.statusCode != 200) {
            setState(() => products = const []);
          } else {
            final j = jsonDecode(res.body);
            final list = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
            setState(() {
              products = list;
              mobilePage = 1;
            });
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => products = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _goToSales() {
    if (_showAllOutlets || selectedOutletKey == null) return;
    final oid = int.tryParse(selectedOutletKey!);
    if (oid == null) return;
    Navigator.of(context).pushNamed('/sales', arguments: {'outlet': oid, 'tab': 'sale'});
  }

  Future<void> _deleteOutlet() async {
    final rec = _selectedOutletRecord;
    if (rec == null) return;
    final id = _asInt(rec['id']);
    final name = (rec['name'] ?? 'Магазин').toString();
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить магазин?'),
        content: Text(
          'Магазин «$name» будет удалён безвозвратно.\n'
          'Все остатки товаров (включая корзину) автоматически вернутся на склад.\n'
          'История продаж по этому магазину будет удалена.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => deleteOutletLoading = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.delete('inventory/outlets/$id/');
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) {
        final data = _tryJsonMap(res.body);
        throw Exception(_firstApiError(data));
      }
      _snack('Магазин удалён');
      setState(() {
        outlets = outlets.where((o) => _asInt(o['id']) != id).toList();
        selectedOutletKey = 'all';
      });
      await _loadProducts();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => deleteOutletLoading = false);
    }
  }

  Future<void> _openAddOutlet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _AddOutletSheet(
        warehouses: warehouses,
        onCreated: (created) {
          Navigator.pop(ctx);
          setState(() {
            outlets = [...outlets, created];
            selectedOutletKey = 'all';
          });
          _loadProducts();
        },
      ),
    );
  }

  Future<void> _openEditOutlet() async {
    final rec = _selectedOutletRecord;
    if (rec == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _EditOutletSheet(
        outlet: rec,
        onSaved: (updated) {
          Navigator.pop(ctx);
          final id = _asInt(updated['id']) ?? _asInt(rec['id']);
          setState(() {
            outlets = outlets.map((o) {
              if (_asInt(o['id']) == id) return {...o, ...updated};
              return o;
            }).toList();
          });
        },
      ),
    );
  }

  Future<void> _openEditStock(Map<String, dynamic> record) async {
    final sid = _asInt(record['outlet_stock_id']);
    if (sid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _EditStockSheet(
        record: record,
        onSaved: () {
          Navigator.pop(ctx);
          _loadProducts();
        },
      ),
    );
  }

  Future<void> _deleteStock(Map<String, dynamic> record) async {
    final sid = _asInt(record['outlet_stock_id']);
    if (sid == null) return;
    final isTrash = showTrash;
    final qty = _asDouble(record['quantity']) ?? 0;
    final name = (record['product_name'] ?? '—').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTrash ? 'Удалить навсегда? Вернуть на склад?' : 'Переместить в корзину?'),
        content: Text(
          isTrash
              ? 'Вернуть ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 3)} шт «$name» на склад и удалить запись безвозвратно?'
              : 'Запись «$name» будет перемещена в корзину.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isTrash ? 'Удалить навсегда' : 'В корзину'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      final path = 'inventory/outlet-stocks/$sid/${isTrash ? '?force=1' : ''}';
      final res = await api.delete(path);
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) throw Exception('Ошибка');
      _snack(isTrash ? 'Товар возвращён на склад, запись удалена' : 'Запись в корзине');
      _loadProducts();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _restoreStock(Map<String, dynamic> record) async {
    final sid = _asInt(record['outlet_stock_id']);
    if (sid == null) return;
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('inventory/outlet-stocks/$sid/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception();
      _snack('Запись восстановлена');
      _loadProducts();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  Widget _mobileRowActions(Map<String, dynamic> r) {
    final hasStockId = _asInt(r['outlet_stock_id']) != null;
    const compact = BoxConstraints.tightFor(width: 34, height: 34);

    if (showTrash) {
      if (!hasStockId) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 18),
            tooltip: 'Восстановить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            color: Colors.white.withValues(alpha: 0.85),
            onPressed: () => _restoreStock(r),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded, size: 18, color: Color(0xFFF87171)),
            tooltip: 'Удалить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            onPressed: () => _deleteStock(r),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_showAllOutlets)
          IconButton(
            icon: Icon(Icons.shopping_cart_outlined, size: 18, color: _blue.withValues(alpha: 0.9)),
            tooltip: 'В кассу',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            onPressed: _goToSales,
          ),
        if (hasStockId) ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Изменить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            color: Colors.white.withValues(alpha: 0.85),
            onPressed: () => _openEditStock(r),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFF87171)),
            tooltip: 'Удалить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            onPressed: () => _deleteStock(r),
          ),
        ],
      ],
    );
  }

  Widget _mobileProductRow(Map<String, dynamic> r, {required bool isLast}) {
    final name = (r['product_name'] ?? r['name'] ?? '—').toString();
    final sub = _productSubline(r);
    final sku = (r['sku'] ?? '').toString().trim();
    final outletName = (r['outlet_name'] ?? '').toString().trim();
    final qty = _asDouble(r['quantity']) ?? 0;
    final unit = _unitLabel((r['unit'] ?? 'pcs').toString());
    final salePrice = _asDouble(r['sale_price']) ?? 0;
    final isEmpty = qty <= 0;

    final metaParts = <String>[
      if (_showAllOutlets && outletName.isNotEmpty) outletName,
      if (sub != null) sub,
      if (sku.isNotEmpty) 'Арт. $sku',
    ];

    final qtyLabel = qty == qty.roundToDouble() ? '${qty.toInt()} $unit' : '${qty.toStringAsFixed(3)} $unit';
    final priceLabel = salePrice > 0 ? '${salePrice.round()} с.' : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0xFFFB923C).withValues(alpha: 0.06) : null,
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _mobileRowActions(r),
            ],
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metaParts.join(' · '),
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                qtyLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isEmpty ? _qtyZero : _qtyBlue,
                ),
              ),
              const Spacer(),
              Text(
                priceLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _priceGreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fieldBorder = dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    final totalPages = products.isEmpty ? 1 : (products.length / _storesMobilePageSize).ceil();

    if (u == null || !canAccessSection(u, 'stores', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final outletItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: 'all', child: Text('Все магазины')),
      for (final o in outlets)
        if (_asInt(o['id']) != null)
          DropdownMenuItem<String>(
            value: _asInt(o['id'])!.toString(),
            child: Text((o['name'] ?? 'Магазин ${o['id']}').toString(), overflow: TextOverflow.ellipsis),
          ),
    ];

    final emptyText = selectedOutletKey == null
        ? 'Выберите магазин'
        : (_showAllOutlets ? 'Нет товаров в магазинах' : 'В магазине нет товаров');

    final outletLabel = _selectedOutletLabel;

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadWarehouses();
            await _loadOutlets();
            _ensureDefaultOutlet();
            await _loadProducts();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Text('Магазины', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              if (outletLabel != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 16, color: const Color(0xFF60A5FA)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          products.isNotEmpty ? '$outletLabel · ${products.length} поз.' : outletLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _contextBlue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedOutletKey,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        filled: true,
                        fillColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.03),
                      ),
                      items: outletItems,
                      onChanged: (v) {
                        setState(() {
                          selectedOutletKey = v;
                          mobilePage = 1;
                        });
                        _loadProducts();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_canManageOutlets && _selectedOutletRecord != null) ...[
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _openEditOutlet,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: fieldBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Icon(Icons.edit_outlined, color: cs.onSurface.withValues(alpha: 0.85), size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: OutlinedButton(
                        onPressed: deleteOutletLoading ? null : _deleteOutlet,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: deleteOutletLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.delete_outline_rounded, color: cs.error, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _storeLimitReached ? null : _openAddOutlet,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      disabledBackgroundColor: const Color(0xFF3A4558),
                      minimumSize: const Size(0, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() {
                          showTrash = !showTrash;
                          mobilePage = 1;
                        });
                        _loadProducts();
                      },
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: showTrash
                              ? const Color(0xFFEF4444).withValues(alpha: 0.16)
                              : (dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                          border: Border.all(
                            color: showTrash
                                ? const Color(0xFFF87171).withValues(alpha: 0.45)
                                : fieldBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: showTrash ? const Color(0xFFFECACA) : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              showTrash ? 'Корзина' : 'Удалённые',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: showTrash ? const Color(0xFFFECACA) : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (selectedOutletKey != null && !_showAllOutlets && !showTrash)
                    FilledButton.icon(
                      onPressed: _goToSales,
                      icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                      label: const Text('Касса'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading && products.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(emptyText, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_storesBlockBgStart, _storesBlockBgEnd],
                    ),
                    border: Border.all(color: const Color(0xFF94A3B8).withValues(alpha: 0.2)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 4))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.12),
                          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'ТОВАРЫ',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFDBEAFE), letterSpacing: 0.4),
                            ),
                            const Spacer(),
                            Container(
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${products.length}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFDBEAFE)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (loading)
                        const Padding(padding: EdgeInsets.all(16), child: SkeletonListBlock(rows: 3))
                      else
                        Column(
                          children: [
                            for (var i = 0; i < _mobileSlice.length; i++)
                              _mobileProductRow(_mobileSlice[i], isLast: i == _mobileSlice.length - 1),
                          ],
                        ),
                    ],
                  ),
                ),
              if (products.length > _storesMobilePageSize) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: mobilePage > 1 ? () => setState(() => mobilePage--) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text('$mobilePage / $totalPages', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    IconButton(
                      onPressed: mobilePage < totalPages ? () => setState(() => mobilePage++) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddOutletSheet extends StatefulWidget {
  const _AddOutletSheet({required this.warehouses, required this.onCreated});

  final List<Map<String, dynamic>> warehouses;
  final void Function(Map<String, dynamic> created) onCreated;

  @override
  State<_AddOutletSheet> createState() => _AddOutletSheetState();
}

class _EditOutletSheet extends StatefulWidget {
  const _EditOutletSheet({required this.outlet, required this.onSaved});

  final Map<String, dynamic> outlet;
  final void Function(Map<String, dynamic> updated) onSaved;

  @override
  State<_EditOutletSheet> createState() => _EditOutletSheetState();
}

class _EditOutletSheetState extends State<_EditOutletSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController addressCtrl;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: (widget.outlet['name'] ?? '').toString());
    addressCtrl = TextEditingController(text: (widget.outlet['address'] ?? '').toString());
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _asInt(widget.outlet['id']);
    if (id == null) return;
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название')));
      return;
    }
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch(
        'inventory/outlets/$id/',
        body: {
          'name': nameCtrl.text.trim(),
          'address': addressCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      widget.onSaved(data.isNotEmpty ? data : {'id': id, 'name': nameCtrl.text.trim(), 'address': addressCtrl.text.trim()});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Магазин изменён')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Изменить магазин', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название магазина', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Адрес (необязательно)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Сохранить'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ],
        ),
      ),
    );
  }
}

class _AddOutletSheetState extends State<_AddOutletSheet> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  int? warehouseId;
  bool saving = false;

  @override
  void dispose() {
    nameCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название')));
      return;
    }
    if (warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите склад')));
      return;
    }
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/outlets/',
        body: {
          'name': nameCtrl.text.trim(),
          'address': addressCtrl.text.trim(),
          'warehouse': warehouseId,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(_firstApiError(data));
      }
      widget.onCreated(data);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Магазин добавлен')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Добавить магазин', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название магазина', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Адрес (необязательно)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: warehouseId,
              decoration: const InputDecoration(labelText: 'Склад', border: OutlineInputBorder()),
              items: [
                for (final w in widget.warehouses)
                  if (_asInt(w['id']) != null)
                    DropdownMenuItem<int>(
                      value: _asInt(w['id'])!,
                      child: Text((w['name'] ?? 'Склад ${w['id']}').toString()),
                    ),
              ],
              onChanged: (v) => setState(() => warehouseId = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Сохранить'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ],
        ),
      ),
    );
  }
}

class _EditStockSheet extends StatefulWidget {
  const _EditStockSheet({required this.record, required this.onSaved});

  final Map<String, dynamic> record;
  final VoidCallback onSaved;

  @override
  State<_EditStockSheet> createState() => _EditStockSheetState();
}

class _EditStockSheetState extends State<_EditStockSheet> {
  final TextEditingController qtyCtrl = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    qtyCtrl.text = (widget.record['quantity'] ?? '').toString();
  }

  @override
  void dispose() {
    qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sid = _asInt(widget.record['outlet_stock_id']);
    if (sid == null) return;
    final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
    if (q == null || q < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите количество')));
      return;
    }
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('inventory/outlet-stocks/$sid/', body: {'quantity': q});
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Количество изменено')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final name = (widget.record['product_name'] ?? '—').toString();
    final outlet = (widget.record['outlet_name'] ?? '').toString();

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Изменить количество (шт)', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(outlet.isEmpty ? name : '$name — $outlet', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Количество', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Сохранить'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ],
        ),
      ),
    );
  }
}

