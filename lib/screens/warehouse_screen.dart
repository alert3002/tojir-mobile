import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/warehouse_mobile_ui.dart';

const _warehouseMobilePageSize = 10;

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

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  List<Map<String, dynamic>> warehouses = const [];
  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> warehouseOutlets = const [];
  List<Map<String, dynamic>> categories = const [];
  int? selectedCategoryId;
  int mobilePage = 1;

  bool loadingWarehouses = false;
  bool loadingProducts = false;

  int? selectedWarehouseId;
  int? selectedOutletId;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';
  String sortKey = 'name';
  bool hideZero = true;
  bool showTrash = false;
  String brandFilter = '';

  double usdToTjs = 11.5;

  bool addStoreLoading = false;
  final TextEditingController newStoreNameCtrl = TextEditingController();
  final TextEditingController newStoreAddressCtrl = TextEditingController();

  final TextEditingController editSalePriceCtrl = TextEditingController();

  Timer? _searchDebounce;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  int? get _subscriptionMaxStores {
    final u = _user;
    if (u == null) return null;
    final v = u['subscription_max_stores'];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  bool get _storeLimitReached {
    final maxS = _subscriptionMaxStores;
    if (maxS == null) return false;
    return warehouseOutlets.length >= maxS;
  }

  @override
  void initState() {
    super.initState();
    searchCtrl.addListener(_onSearchText);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['brand'] != null) {
        brandFilter = args['brand'].toString();
      }
      await _loadRate();
      await _loadWarehouses();
      await _loadCategories();
      _syncWarehouseFromUser();
      await _loadOutlets();
      await _loadProducts();
    });
  }

  void _syncWarehouseFromUser() {
    final u = _user;
    if (u == null) return;
    final wh = u['warehouse'];
    final wid = wh is int ? wh : (wh is num ? wh.toInt() : int.tryParse(wh?.toString() ?? ''));
    if (wid != null && selectedWarehouseId == null) {
      setState(() => selectedWarehouseId = wid);
    } else if (wid == null && selectedWarehouseId == null && warehouses.isNotEmpty) {
      final first = _asInt(warehouses.first['id']);
      if (first != null) setState(() => selectedWarehouseId = first);
    }
  }

  void _onSearchText() {
    final v = searchCtrl.text;
    if (v == search) return;
    search = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _loadProducts();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchCtrl.dispose();
    newStoreNameCtrl.dispose();
    newStoreAddressCtrl.dispose();
    editSalePriceCtrl.dispose();
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

  Future<void> _loadRate() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/rate/');
      if (!mounted || res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final v = d['usd_to_tjs'];
      final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
      if (n != null && n > 0) setState(() => usdToTjs = n);
    } catch (_) {}
  }

  Future<void> _loadWarehouses() async {
    setState(() => loadingWarehouses = true);
    try {
      final res = await context.read<ApiClient>().get('inventory/warehouses/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => warehouses = items);
        _syncWarehouseFromUser();
      }
    } catch (_) {
      if (mounted) setState(() => warehouses = const []);
    } finally {
      if (mounted) setState(() => loadingWarehouses = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/categories/');
      if (!mounted || res.statusCode != 200) return;
      final d = jsonDecode(res.body);
      final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
      final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      setState(() => categories = items);
    } catch (_) {
      if (mounted) setState(() => categories = const []);
    }
  }

  Future<void> _loadOutlets() async {
    final wid = selectedWarehouseId ?? _asInt(_user?['warehouse']);
    if (wid == null) {
      setState(() {
        warehouseOutlets = const [];
        selectedOutletId = null;
      });
      return;
    }
    try {
      final res = await context.read<ApiClient>().get('inventory/outlets?warehouse=$wid');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          warehouseOutlets = items;
          if (selectedOutletId != null && !items.any((o) => _asInt(o['id']) == selectedOutletId)) {
            selectedOutletId = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => warehouseOutlets = const []);
    }
  }

  Future<void> _loadProducts() async {
    final wid = selectedWarehouseId ?? _asInt(_user?['warehouse']);
    if (wid == null) {
      setState(() => products = const []);
      return;
    }
    setState(() => loadingProducts = true);
    try {
      final qp = <String, String>{'warehouse': wid.toString()};
      if (search.trim().isNotEmpty) qp['search'] = search.trim();
      if (brandFilter.trim().isNotEmpty) qp['brand'] = brandFilter.trim();
      if (selectedOutletId != null) qp['outlet'] = selectedOutletId.toString();
      if (sortKey.isNotEmpty && sortKey != 'name') qp['ordering'] = sortKey;
      if (showTrash) {
        qp['trash'] = '1';
      } else if (hideZero) {
        qp['hide_zero'] = '1';
      }
      final path = 'inventory/products/?${Uri(queryParameters: qp).query}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          products = items;
          mobilePage = 1;
        });
      } else {
        setState(() {
          products = const [];
          mobilePage = 1;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          products = const [];
          mobilePage = 1;
        });
      }
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  List<Map<String, dynamic>> _sortedProducts(bool canSeeWarehouseQty) {
    final arr = [...products];
    double stockOf(Map<String, dynamic> p) {
      if (selectedOutletId != null) return _asDouble(p['outlet_stock_quantity']) ?? 0;
      final stores = ((p['outlets_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
          .fold<double>(0, (s, o) => s + (_asDouble(o['quantity']) ?? 0));
      final wh = canSeeWarehouseQty ? (_asDouble(p['quantity']) ?? 0) : 0;
      return wh + stores;
    }

    String nameOf(Map<String, dynamic> p) => (p['name'] ?? '').toString().toLowerCase();
    double soldOf(Map<String, dynamic> p) => _asDouble(p['sold_qty']) ?? 0;
    int idOf(Map<String, dynamic> p) => _asInt(p['id']) ?? 0;

    arr.sort((a, b) {
      var d = 0;
      switch (sortKey) {
        case 'stock_asc':
          d = stockOf(a).compareTo(stockOf(b));
        case 'stock_desc':
          d = stockOf(b).compareTo(stockOf(a));
        case 'sold_asc':
          d = soldOf(a).compareTo(soldOf(b));
        case 'sold_desc':
          d = soldOf(b).compareTo(soldOf(a));
        case 'new':
          d = idOf(b).compareTo(idOf(a));
        case 'old':
          d = idOf(a).compareTo(idOf(b));
        default:
          d = nameOf(a).compareTo(nameOf(b));
      }
      if (d != 0) return d;
      return nameOf(a).compareTo(nameOf(b));
    });
    return arr;
  }

  WarehouseStats? _warehouseStats() {
    if (showTrash) return null;
    var warehouseQty = 0.0;
    var storeQty = 0.0;
    var lowStock = 0;
    for (final p in products) {
      final wq = _asDouble(p['quantity']) ?? 0;
      warehouseQty += wq;
      if (wq > 0 && wq <= 5) lowStock++;
      if (selectedOutletId != null) {
        storeQty += _asDouble(p['outlet_stock_quantity']) ?? 0;
      } else {
        final summary = (p['outlets_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
        storeQty += summary.fold<double>(0, (s, o) => s + (_asDouble(o['quantity']) ?? 0));
      }
    }
    String? storeLabel;
    if (selectedOutletId != null) {
      for (final o in warehouseOutlets) {
        if (_asInt(o['id']) == selectedOutletId) {
          storeLabel = (o['name'] ?? '').toString();
          break;
        }
      }
    }
    return WarehouseStats(
      positions: products.length,
      warehouseQty: warehouseQty.round(),
      storeQty: storeQty.round(),
      lowStock: lowStock,
      stores: warehouseOutlets.length,
      storeLabel: storeLabel,
    );
  }

  String _warehouseDisplayName(Map<String, dynamic> u) {
    final wn = (u['warehouse_name'] as String?)?.trim();
    if (wn != null && wn.isNotEmpty) return wn;
    final wid = selectedWarehouseId ?? _asInt(u['warehouse']);
    for (final w in warehouses) {
      if (_asInt(w['id']) == wid) return (w['name'] ?? 'Склад').toString();
    }
    return 'Склад';
  }

  Future<bool> _connectStore() async {
    final wid = selectedWarehouseId ?? _asInt(_user?['warehouse']);
    if (wid == null) {
      _snack('Нет склада для подключения', error: true);
      return false;
    }
    final name = newStoreNameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Введите название', error: true);
      return false;
    }
    setState(() => addStoreLoading = true);
    try {
      final res = await context.read<ApiClient>().post(
            'inventory/outlets/',
            body: {
              'name': name,
              'address': newStoreAddressCtrl.text.trim(),
              'warehouse': wid,
            },
          );
      if (!mounted) return false;
      if (res.statusCode != 200 && res.statusCode != 201) {
        final err = _tryJsonMap(res.body);
        final d = err['detail'];
        String? msg;
        if (d is String) msg = d;
        if (d is List && d.isNotEmpty) msg = d.first.toString();
        msg ??= (err['name'] is List ? (err['name'] as List).first?.toString() : null) ?? 'Ошибка сохранения';
        throw Exception(msg);
      }
      final created = jsonDecode(res.body) as Map<String, dynamic>;
      _snack('Магазин подключён к складу');
      setState(() => warehouseOutlets = [...warehouseOutlets, created]);
      newStoreNameCtrl.clear();
      newStoreAddressCtrl.clear();
      return true;
    } catch (e) {
      _snack(e.toString(), error: true);
      return false;
    } finally {
      if (mounted) setState(() => addStoreLoading = false);
    }
  }

  Future<void> _openDistribute(Map<String, dynamic> record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DistributeBottomSheet(
        record: record,
        outlets: warehouseOutlets,
        warehouseId: selectedWarehouseId ?? _asInt(_user?['warehouse']),
        api: context.read<ApiClient>(),
        onDone: (String? err) async {
          Navigator.of(ctx).pop();
          if (err == null) {
            _snack('Товар распределён по магазинам');
            await _loadProducts();
          } else {
            _snack(err, error: true);
          }
        },
      ),
    );
  }

  double _costPriceTjs(Map<String, dynamic> record) {
    final lastPrice = record['last_arrival_unit_price'] != null
        ? (_asDouble(record['last_arrival_unit_price']) ?? 0)
        : (_asDouble(record['cost_price']) ?? 0);
    final lastCur = (record['last_arrival_currency'] ?? 'TJS').toString();
    if (lastCur == 'USD' && usdToTjs > 0) return lastPrice * usdToTjs;
    return lastPrice;
  }

  void _openEdit(Map<String, dynamic> record) {
    final sp = _asDouble(record['sale_price']);
    if (sp != null && sp > 0) {
      editSalePriceCtrl.text = sp == sp.truncateToDouble() ? sp.toInt().toString() : sp.toString();
    } else {
      editSalePriceCtrl.clear();
    }
    final id = _asInt(record['id']);
    if (id == null) return;
    final q0 = _asDouble(record['quantity']) ?? 0;
    final qtyText = '${q0.toStringAsFixed(q0 % 1 == 0 ? 0 : 3)} ${_unitLabel(record['unit']?.toString())}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProductBottomSheet(
        productId: id,
        productName: (record['name'] ?? '').toString(),
        quantityText: qtyText,
        costTjs: _costPriceTjs(record),
        salePriceCtrl: editSalePriceCtrl,
        usdToTjs: usdToTjs,
        api: context.read<ApiClient>(),
        onSaved: () async {
          Navigator.of(ctx).pop();
          _snack('Товар обновлён');
          await _loadProducts();
        },
        onError: (e) => _snack(e, error: true),
      ),
    );
  }

  Future<void> _showConnectStoreSheet() async {
    var showForm = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final cs = Theme.of(ctx).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppShape.sheetTop,
            ),
            padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Магазины склада', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  const SizedBox(height: 12),
                  if (warehouseOutlets.isEmpty)
                    Text('Нет подключённых магазинов', style: TextStyle(color: cs.onSurfaceVariant))
                  else
                    ...warehouseOutlets.map((o) {
                      final addr = (o['address'] ?? '').toString().trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: (o['name'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                              if (addr.isNotEmpty) TextSpan(text: ' — $addr', style: TextStyle(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      );
                    }),
                  if (!showForm)
                    OutlinedButton.icon(
                      onPressed: _storeLimitReached
                          ? null
                          : () => setM(() => showForm = true),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить новый магазин'),
                    )
                  else ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: newStoreNameCtrl,
                      decoration: const InputDecoration(labelText: 'Название магазина *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newStoreAddressCtrl,
                      decoration: const InputDecoration(labelText: 'Адрес (необязательно)'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: addStoreLoading
                                ? null
                                : () async {
                                    final ok = await _connectStore();
                                    if (ctx.mounted && ok) Navigator.of(ctx).pop();
                                  },
                            child: Text(addStoreLoading ? 'Подключение…' : 'Подключить'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: addStoreLoading
                                ? null
                                : () {
                                    newStoreNameCtrl.clear();
                                    newStoreAddressCtrl.clear();
                                    setM(() => showForm = false);
                                  },
                            child: const Text('Отмена'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _doDeleteProduct(Map<String, dynamic> record, {required bool force}) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    final path = force ? 'inventory/products/$id/?force=1' : 'inventory/products/$id/';
    final res = await context.read<ApiClient>().delete(path);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = _tryJsonMap(res.body);
      throw Exception(err['detail']?.toString() ?? err['message']?.toString() ?? 'Ошибка');
    }
  }

  Future<void> _handleDelete(Map<String, dynamic> record) async {
    final isTrash = showTrash;
    final name = (record['name'] ?? '—').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTrash ? 'Удалить навсегда?' : 'Удалить товар?'),
        content: Text(
          isTrash
              ? 'Товар «$name» будет удалён из базы безвозвратно. Продолжить?'
              : 'Товар «$name» переместить в корзину?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _doDeleteProduct(record, force: false);
      if (!mounted) return;
      _snack(isTrash ? 'Товар удалён навсегда' : 'Товар в корзине');
      await _loadProducts();
    } catch (e) {
      final msg = e.toString();
      if (isTrash && msg.contains('продажи, поступления или перемещения')) {
        if (!mounted) return;
        final ok2 = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить всё безвозвратно?'),
            content: Text(
              'По товару «$name» есть продажи, поступления или перемещения. Удалить товар и все связанные записи из базы навсегда?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );
        if (ok2 == true && mounted) {
          try {
            await _doDeleteProduct(record, force: true);
            _snack('Товар и связанные данные удалены навсегда');
            await _loadProducts();
          } catch (e2) {
            _snack(e2.toString(), error: true);
          }
        }
      } else {
        _snack(msg, error: true);
      }
    }
  }

  Future<void> _handleRestore(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    try {
      final res = await context.read<ApiClient>().patch('inventory/products/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception();
      _snack('Товар восстановлен');
      await _loadProducts();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  void _goProductDetail(int id) {
    Navigator.of(context).pushNamed('/warehouse/product/$id');
  }

  String _unitLabel(String? u) => _unitLabels[u ?? ''] ?? 'шт';

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'warehouse', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
    }

    final hasFixedWarehouse = u['warehouse'] != null;
    final isSeller = u['role'] == 'seller';
    final canManageStores = !isSeller;
    final canSeeTrash = !isSeller;
    final canSeeWarehouseQty = !isSeller;
    final stats = _warehouseStats();
    final sorted = _sortedProducts(canSeeWarehouseQty);
    final mobileSlice = sorted.skip((mobilePage - 1) * _warehouseMobilePageSize).take(_warehouseMobilePageSize).toList();
    const sortOptions = <(String, String)>[
      ('name', 'По имени'),
      ('stock_asc', 'Остаток: мало → много'),
      ('stock_desc', 'Остаток: много → мало'),
      ('sold_desc', 'Продажи: больше'),
      ('sold_asc', 'Продажи: меньше'),
      ('new', 'Сначала новые'),
      ('old', 'Сначала старые'),
    ];

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadWarehouses();
            await _loadCategories();
            _syncWarehouseFromUser();
            await _loadOutlets();
            await _loadProducts();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            children: [
              WarehouseHero(
                dark: dark,
                cs: cs,
                isSeller: isSeller,
                warehouseName: _warehouseDisplayName(u),
                storeCount: warehouseOutlets.length,
                stats: stats,
                showTrash: showTrash,
                onArrivals: () => Navigator.of(context).pushNamed('/arrivals'),
                onTransfers: () => Navigator.of(context).pushNamed('/transfers'),
                onStores: () => Navigator.of(context).pushNamed('/stores'),
              ),
              WarehouseFiltersCard(
                cs: cs,
                dark: dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!showTrash && canManageStores) ...[
                      WarehouseStoreChips(
                        outlets: warehouseOutlets,
                        selectedOutletId: selectedOutletId,
                        canAdd: true,
                        addDisabled: _storeLimitReached,
                        onAdd: _showConnectStoreSheet,
                        onSelectAll: () {
                          setState(() {
                            selectedOutletId = null;
                            mobilePage = 1;
                          });
                          _loadProducts();
                        },
                        onSelectOutlet: (id) {
                          setState(() {
                            selectedOutletId = selectedOutletId == id ? null : id;
                            mobilePage = 1;
                          });
                          _loadProducts();
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!hasFixedWarehouse && !isSeller) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey<int?>(selectedWarehouseId),
                        initialValue: selectedWarehouseId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Склад',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: warehouses.map((w) {
                          final id = _asInt(w['id']);
                          if (id == null) return null;
                          return DropdownMenuItem(
                            value: id,
                            child: Text((w['name'] ?? 'Склад $id').toString()),
                          );
                        }).whereType<DropdownMenuItem<int>>().toList(),
                        onChanged: (v) async {
                          setState(() {
                            selectedWarehouseId = v;
                            selectedOutletId = null;
                          });
                          await _loadOutlets();
                          await _loadProducts();
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              hintText: isSeller ? 'Найти товар…' : 'Поиск: имя / модель / артикул',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 36,
                          height: 40,
                          child: IconButton.outlined(
                            onPressed: loadingProducts ? null : _loadProducts,
                            icon: loadingProducts
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded, size: 18),
                            style: IconButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(sortKey),
                      initialValue: sortKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        for (final o in sortOptions)
                          DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          sortKey = v;
                          mobilePage = 1;
                        });
                        _loadProducts();
                      },
                    ),
                    if (canSeeTrash)
                      WarehouseTrashTabs(
                        showTrash: showTrash,
                        onChanged: (v) {
                          setState(() {
                            showTrash = v;
                            mobilePage = 1;
                          });
                          _loadProducts();
                        },
                      ),
                    if (!showTrash) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Switch(
                            value: hideZero,
                            onChanged: (v) {
                              setState(() => hideZero = v);
                              _loadProducts();
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Скрыть нулевой остаток',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (loadingProducts && products.isEmpty)
                const SkeletonListBlock(rows: 6)
              else if (sorted.isEmpty)
                WarehouseFiltersCard(
                  cs: cs,
                  dark: dark,
                  child: Text('Нет товаров', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                )
              else ...[
                for (final record in mobileSlice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WarehouseMobileProductCard(
                      record: record,
                      cs: cs,
                      dark: dark,
                      warehouseOutlets: warehouseOutlets,
                      filterOutletId: selectedOutletId,
                      usdToTjs: usdToTjs,
                      showTrash: showTrash,
                      isSeller: isSeller,
                      canSeeWarehouseQty: canSeeWarehouseQty,
                      unitLabel: _unitLabel,
                      onTap: showTrash ? null : () {
                        final id = _asInt(record['id']);
                        if (id != null) _goProductDetail(id);
                      },
                      onDistribute: (!showTrash && !isSeller) ? () => _openDistribute(record) : null,
                      onEdit: (!showTrash && !isSeller) ? () => _openEdit(record) : null,
                      onDelete: () => _handleDelete(record),
                      onRestore: showTrash ? () => _handleRestore(record) : null,
                    ),
                  ),
                if (sorted.length > _warehouseMobilePageSize)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: mobilePage > 1 ? () => setState(() => mobilePage--) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Text('$mobilePage / ${(sorted.length / _warehouseMobilePageSize).ceil()}'),
                        IconButton(
                          onPressed: mobilePage * _warehouseMobilePageSize < sorted.length
                              ? () => setState(() => mobilePage++)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _tryJsonMap(String body) {
  try {
    final j = jsonDecode(body.isEmpty ? '{}' : body);
    return j is Map<String, dynamic> ? j : {};
  } catch (_) {
    return {};
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

class _DistributeBottomSheet extends StatefulWidget {
  const _DistributeBottomSheet({
    required this.record,
    required this.outlets,
    required this.warehouseId,
    required this.api,
    required this.onDone,
  });

  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> outlets;
  final int? warehouseId;
  final ApiClient api;
  final void Function(String? err) onDone;

  @override
  State<_DistributeBottomSheet> createState() => _DistributeBottomSheetState();
}

class _DistributeBottomSheetState extends State<_DistributeBottomSheet> {
  late final List<TextEditingController> _qtyCtrls;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrls = List.generate(widget.outlets.length, (_) => TextEditingController(text: '0'));
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final wid = widget.warehouseId;
    if (wid == null) {
      widget.onDone('Склад не выбран');
      return;
    }
    final pid = _asInt(widget.record['id']);
    if (pid == null) {
      widget.onDone('Ошибка товара');
      return;
    }
    final whQty = _asDouble(widget.record['quantity']) ?? 0;
    final toSend = <({int outletId, int qty})>[];
    for (var i = 0; i < widget.outlets.length; i++) {
      final oid = _asInt(widget.outlets[i]['id']);
      if (oid == null) continue;
      final q = double.tryParse(_qtyCtrls[i].text.replaceAll(',', '.')) ?? 0;
      final qi = q < 0 ? 0 : q.floor();
      if (qi > 0) toSend.add((outletId: oid, qty: qi));
    }
    if (toSend.isEmpty) {
      widget.onDone('Укажите количество для магазина');
      return;
    }
    final total = toSend.fold<int>(0, (s, x) => s + x.qty);
    if (total > whQty) {
      widget.onDone('На складе только ${whQty % 1 == 0 ? whQty.toInt() : whQty} шт');
      return;
    }
    setState(() => _loading = true);
    try {
      for (final x in toSend) {
        final res = await widget.api.post(
          'inventory/transfers/',
          body: {
            'warehouse': wid,
            'product': pid,
            'from_outlet': null,
            'to_outlet': x.outletId,
            'quantity': x.qty,
          },
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          final err = _tryJsonMap(res.body);
          final qe = err['quantity'];
          String? msg;
          if (qe is List && qe.isNotEmpty) msg = qe.first.toString();
          msg ??= err['detail']?.toString() ?? 'Ошибка';
          widget.onDone(msg);
          return;
        }
      }
      widget.onDone(null);
    } catch (e) {
      widget.onDone(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final whQty = _asDouble(widget.record['quantity']) ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppShape.sheetTop,
      ),
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Распределить по магазинам',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              (widget.record['name'] ?? '').toString(),
              style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
            Text(
              'На складе: ${whQty % 1 == 0 ? whQty.toInt() : whQty} шт',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (widget.outlets.isEmpty)
              Text('Магазины не найдены — подключите магазины к складу.', style: TextStyle(color: cs.onSurfaceVariant))
            else
              ...List.generate(widget.outlets.length, (i) {
                final o = widget.outlets[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _qtyCtrls[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: (o['name'] ?? 'Магазин').toString(),
                      hintText: '0',
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _loading || widget.outlets.isEmpty ? null : _submit,
                    child: Text(_loading ? 'Отправка…' : 'Распределить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
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

class _EditProductBottomSheet extends StatefulWidget {
  const _EditProductBottomSheet({
    required this.productId,
    required this.productName,
    required this.quantityText,
    required this.costTjs,
    required this.salePriceCtrl,
    required this.usdToTjs,
    required this.api,
    required this.onSaved,
    required this.onError,
  });

  final int productId;
  final String productName;
  final String quantityText;
  final double costTjs;
  final TextEditingController salePriceCtrl;
  final double usdToTjs;
  final ApiClient api;
  final Future<void> Function() onSaved;
  final void Function(String) onError;

  @override
  State<_EditProductBottomSheet> createState() => _EditProductBottomSheetState();
}

class _EditProductBottomSheetState extends State<_EditProductBottomSheet> {
  bool _loading = false;
  String? _saleError;
  final FocusNode _saleFocus = FocusNode();

  static double? _parseSaleText(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
    return double.tryParse(t);
  }

  static bool _isZeroPriceText(String t) {
    final z = t.trim().replaceAll(',', '.');
    return z == '0' || z == '0.0' || z == '0.00' || RegExp(r'^0+\.0+$').hasMatch(z);
  }

  @override
  void initState() {
    super.initState();
    widget.salePriceCtrl.addListener(_onSaleChanged);
    _saleFocus.addListener(_onSaleFocus);
    _validateSale(showEmpty: false);
  }

  @override
  void dispose() {
    widget.salePriceCtrl.removeListener(_onSaleChanged);
    _saleFocus.removeListener(_onSaleFocus);
    _saleFocus.dispose();
    super.dispose();
  }

  void _onSaleFocus() {
    if (!_saleFocus.hasFocus) return;
    if (_isZeroPriceText(widget.salePriceCtrl.text)) {
      widget.salePriceCtrl.clear();
      if (mounted) setState(() {});
    }
  }

  void _onSaleChanged() {
    _validateSale(showEmpty: false);
  }

  bool _validateSale({required bool showEmpty}) {
    final raw = widget.salePriceCtrl.text.trim();
    String? err;
    if (raw.isEmpty) {
      err = showEmpty ? 'Введите цену продажи' : null;
    } else {
      final sale = _parseSaleText(raw);
      if (sale == null || sale <= 0) {
        err = 'Введите цену продажи (только цифры)';
      } else if (widget.costTjs > 0 && sale <= widget.costTjs) {
        err = 'Цена продажи должна быть выше цены закупки (${widget.costTjs.toStringAsFixed(2)} TJS)';
      }
    }
    if (mounted && _saleError != err) setState(() => _saleError = err);
    return err == null;
  }

  Future<void> _save() async {
    if (!_validateSale(showEmpty: true)) return;
    final sale = _parseSaleText(widget.salePriceCtrl.text) ?? 0;
    setState(() => _loading = true);
    try {
      final res = await widget.api.patch(
        'inventory/products/${widget.productId}/',
        body: {'sale_price': sale},
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = _tryJsonMap(res.body);
        widget.onError(err['detail']?.toString() ?? 'Ошибка сохранения');
        return;
      }
      await widget.onSaved();
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final sale = _parseSaleText(widget.salePriceCtrl.text) ?? 0;
    final saleUsd = widget.usdToTjs > 0 ? sale / widget.usdToTjs : null;
    final costTjs = widget.costTjs;
    final costUsd = widget.usdToTjs > 0 ? costTjs / widget.usdToTjs : null;
    final profitTjs = sale - costTjs;
    final profitUsd = widget.usdToTjs > 0 ? profitTjs / widget.usdToTjs : null;
    final profitColor = profitTjs > 0 ? const Color(0xFF52C41A) : const Color(0xFFFF4D4F);

    final fieldFill = cs.surfaceContainerHighest.withValues(alpha: dark ? 0.35 : 0.55);
    InputDecoration fieldDecoration(String label, {String? suffix}) => InputDecoration(
          labelText: label,
          suffixText: suffix,
          labelStyle: TextStyle(color: cs.onSurfaceVariant),
          filled: true,
          fillColor: fieldFill,
        );

    Widget readOnlyRow(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppShape.sheetTop,
      ),
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Изменить товар', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 8),
          readOnlyRow('Название', widget.productName.isEmpty ? '—' : widget.productName),
          readOnlyRow(
            'Цена закупки',
            costTjs > 0
                ? '${costTjs.toStringAsFixed(2)} TJS${costUsd != null ? ' / ≈ ${costUsd.toStringAsFixed(2)} USD' : ''}'
                : '—',
          ),
          readOnlyRow('Остаток', widget.quantityText),
          TextField(
            controller: widget.salePriceCtrl,
            focusNode: _saleFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: TextStyle(color: cs.onSurface),
            decoration: fieldDecoration('Цена продажи (TJS)', suffix: 'TJS').copyWith(errorText: _saleError),
          ),
          Text(
            '≈ ${saleUsd != null ? saleUsd.toStringAsFixed(2) : '—'} USD (курс 1 USD = ${widget.usdToTjs.toStringAsFixed(2)} TJS)',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Ваш доход: ${profitTjs.toStringAsFixed(2)} TJS${profitUsd != null ? ' / ≈ ${profitUsd.toStringAsFixed(2)} USD' : ''}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: profitColor),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: (_loading || _saleError != null) ? null : _save,
                  child: Text(_loading ? 'Сохранение…' : 'Сохранить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
