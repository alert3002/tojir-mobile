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

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  List<Map<String, dynamic>> warehouses = const [];
  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> warehouseOutlets = const [];

  bool loadingWarehouses = false;
  bool loadingProducts = false;

  int? selectedWarehouseId;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';
  bool hideZero = true;
  bool showTrash = false;

  double usdToTjs = 11.5;

  bool addStoreLoading = false;
  final TextEditingController newStoreNameCtrl = TextEditingController();
  final TextEditingController newStoreAddressCtrl = TextEditingController();

  final TextEditingController editNameCtrl = TextEditingController();
  final TextEditingController editSalePriceCtrl = TextEditingController();
  final TextEditingController editQtyCtrl = TextEditingController();

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
      await _loadRate();
      await _loadWarehouses();
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
    editNameCtrl.dispose();
    editSalePriceCtrl.dispose();
    editQtyCtrl.dispose();
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

  Future<void> _loadOutlets() async {
    final wid = selectedWarehouseId ?? _asInt(_user?['warehouse']);
    if (wid == null) {
      setState(() => warehouseOutlets = const []);
      return;
    }
    try {
      final res = await context.read<ApiClient>().get('inventory/outlets?warehouse=$wid');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => warehouseOutlets = items);
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
        setState(() => products = items);
      } else {
        setState(() => products = const []);
      }
    } catch (_) {
      if (mounted) setState(() => products = const []);
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
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

  void _openEdit(Map<String, dynamic> record) {
    editNameCtrl.text = (record['name'] ?? '').toString();
    editSalePriceCtrl.text = (_asDouble(record['sale_price']) ?? 0).toString();
    final q0 = _asDouble(record['quantity']) ?? 0;
    editQtyCtrl.text = q0.toStringAsFixed(q0 % 1 == 0 ? 0 : 3);
    final id = _asInt(record['id']);
    if (id == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProductBottomSheet(
        productId: id,
        nameCtrl: editNameCtrl,
        salePriceCtrl: editSalePriceCtrl,
        qtyCtrl: editQtyCtrl,
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
          final dark = Theme.of(ctx).brightness == Brightness.dark;
          final cs = Theme.of(ctx).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF0B1220) : Colors.white,
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
                    const SizedBox(height: 14),
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
    final maxS = _subscriptionMaxStores;

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadWarehouses();
            _syncWarehouseFromUser();
            await _loadOutlets();
            await _loadProducts();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              Text(
                'Склад — остатки товаров',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
              ),
              const SizedBox(height: 14),
              _WarehouseCard(
                dark: dark,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!showTrash) ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: _storeLimitReached
                                ? 'Лимит магазинов по тарифу исчерпан. Повысьте тариф в разделе «Тарифы».'
                                : '',
                            child: FilledButton.icon(
                              onPressed: _storeLimitReached ? null : _showConnectStoreSheet,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                disabledBackgroundColor: cs.surfaceContainerHighest,
                              ),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Подключить магазин'),
                            ),
                          ),
                          if (warehouseOutlets.isNotEmpty) ...[
                            ...warehouseOutlets.map((o) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: AppShape.br,
                                  color: const Color(0xFF2563EB).withValues(alpha: dark ? 0.25 : 0.12),
                                  border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.45)),
                                ),
                                child: Text(
                                  (o['name'] ?? '').toString(),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
                                ),
                              );
                            }),
                            if (maxS != null && maxS > 0)
                              Text(
                                '${warehouseOutlets.length}/$maxS',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!hasFixedWarehouse) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey<int?>(selectedWarehouseId),
                        initialValue: selectedWarehouseId,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true, labelText: 'Склад'),
                        items: warehouses.map((w) {
                          final id = _asInt(w['id']);
                          if (id == null) return null;
                          return DropdownMenuItem(
                            value: id,
                            child: Text((w['name'] ?? 'Склад $id').toString()),
                          );
                        }).whereType<DropdownMenuItem<int>>().toList(),
                        onChanged: (v) async {
                          setState(() => selectedWarehouseId = v);
                          await _loadOutlets();
                          await _loadProducts();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Поиск по имени / модели / артикулу',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('Товары')),
                              ButtonSegment(value: true, label: Text('Корзина')),
                            ],
                            selected: {showTrash},
                            onSelectionChanged: (s) {
                              setState(() => showTrash = s.first);
                              _loadProducts();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (!showTrash) ...[
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: hideZero,
                        onChanged: (v) {
                          setState(() => hideZero = v);
                          _loadProducts();
                        },
                        title: Text('Скрывать товары с нулевым остатком', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (loadingProducts && products.isEmpty) const SkeletonListBlock(rows: 8)
else
                _WarehouseProductsTable(
                  dark: dark,
                  cs: cs,
                  products: products,
                  warehouseOutlets: warehouseOutlets,
                  showTrash: showTrash,
                  usdToTjs: usdToTjs,
                  unitLabel: _unitLabel,
                  onRowTap: showTrash ? null : _goProductDetail,
                  onDistribute: (!showTrash) ? _openDistribute : null,
                  onEdit: (!showTrash) ? _openEdit : null,
                  onDelete: _handleDelete,
                  onRestore: showTrash ? _handleRestore : null,
                ),
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

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({required this.dark, required this.cs, required this.child});
  final bool dark;
  final ColorScheme cs;
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
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _WarehouseProductsTable extends StatelessWidget {
  const _WarehouseProductsTable({
    required this.dark,
    required this.cs,
    required this.products,
    required this.warehouseOutlets,
    required this.showTrash,
    required this.usdToTjs,
    required this.unitLabel,
    this.onRowTap,
    this.onDistribute,
    this.onEdit,
    required this.onDelete,
    this.onRestore,
  });

  final bool dark;
  final ColorScheme cs;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> warehouseOutlets;
  final bool showTrash;
  final double usdToTjs;
  final String Function(String?) unitLabel;
  final void Function(int id)? onRowTap;
  final void Function(Map<String, dynamic>)? onDistribute;
  final void Function(Map<String, dynamic>)? onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>)? onRestore;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _WarehouseCard(
        dark: dark,
        cs: cs,
        child: Text('Нет товаров', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return _WarehouseCard(
      dark: dark,
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: products.take(40).map((record) {
          return _ProductRowCard(
            record: record,
            cs: cs,
            dark: dark,
            warehouseOutlets: warehouseOutlets,
            showTrash: showTrash,
            usdToTjs: usdToTjs,
            unitLabel: unitLabel,
            onTap: onRowTap != null && _asInt(record['id']) != null ? () => onRowTap!(_asInt(record['id'])!) : null,
            onDistribute: onDistribute,
            onEdit: onEdit,
            onDelete: onDelete,
            onRestore: onRestore,
          );
        }).toList(),
      ),
    );
  }
}

class _ProductRowCard extends StatelessWidget {
  const _ProductRowCard({
    required this.record,
    required this.cs,
    required this.dark,
    required this.warehouseOutlets,
    required this.showTrash,
    required this.usdToTjs,
    required this.unitLabel,
    this.onTap,
    this.onDistribute,
    this.onEdit,
    required this.onDelete,
    this.onRestore,
  });

  final Map<String, dynamic> record;
  final ColorScheme cs;
  final bool dark;
  final List<Map<String, dynamic>> warehouseOutlets;
  final bool showTrash;
  final double usdToTjs;
  final String Function(String?) unitLabel;
  final VoidCallback? onTap;
  final void Function(Map<String, dynamic>)? onDistribute;
  final void Function(Map<String, dynamic>)? onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>)? onRestore;

  @override
  Widget build(BuildContext context) {
    final summary = (record['outlets_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    final summaryByName = <String, double>{};
    for (final o in summary) {
      final n = (o['outlet_name'] ?? '').toString();
      summaryByName[n] = _asDouble(o['quantity']) ?? 0;
    }
    final inStores = summary.fold<double>(0, (s, o) => s + (_asDouble(o['quantity']) ?? 0));
    final whQty = _asDouble(record['quantity']) ?? 0;
    final total = whQty + inStores;
    final u = (record['unit'] ?? 'pcs').toString();
    final ul = unitLabel(u);

    final tjs = _asDouble(record['total_purchase_tjs']) ?? 0;
    final usdPur = _asDouble(record['total_purchase_usd']) ?? 0;
    final hasPurchase = tjs > 0 || usdPur > 0;
    final totalTjs = tjs + usdPur * usdToTjs;
    final totalUsd = usdToTjs > 0 ? totalTjs / usdToTjs : 0;
    final lastPrice = record['last_arrival_unit_price'] != null
        ? (_asDouble(record['last_arrival_unit_price']) ?? 0)
        : (_asDouble(record['cost_price']) ?? 0);
    final lastCur = (record['last_arrival_currency'] ?? 'TJS').toString();
    final costTjs = lastCur == 'USD' && usdToTjs > 0 ? lastPrice * usdToTjs : lastPrice;
    final costUsd = usdToTjs > 0 ? costTjs / usdToTjs : 0;
    final saleTjs = _asDouble(record['sale_price']) ?? 0;
    final saleUsd = usdToTjs > 0 ? saleTjs / usdToTjs : 0;

    final hasStoreQty = warehouseOutlets.any((o) => (summaryByName[(o['name'] ?? '').toString()] ?? 0) > 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        borderRadius: AppShape.br,
        child: InkWell(
          borderRadius: AppShape.br,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (record['name'] ?? '—').toString(),
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface),
                          ),
                          if ((record['model'] ?? '').toString().trim().isNotEmpty)
                            Text(
                              record['model'].toString(),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if ((record['brand'] ?? '').toString().isNotEmpty)
                                _MiniTag(record['brand'].toString(), cs),
                              if ((record['color'] ?? '').toString().isNotEmpty)
                                _MiniTag(record['color'].toString(), cs),
                              if ((record['memory'] ?? '').toString().isNotEmpty)
                                _MiniTag(record['memory'].toString(), cs, blue: true),
                              if ((record['ram'] ?? '').toString().isNotEmpty)
                                _MiniTag(record['ram'].toString(), cs, blue: true),
                              if ((record['size'] ?? '').toString().isNotEmpty)
                                _MiniTag(record['size'].toString(), cs, purple: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        if (showTrash && onRestore != null)
                          IconButton(
                            tooltip: 'Восстановить',
                            icon: const Icon(Icons.undo_rounded, size: 20),
                            onPressed: () => onRestore!(record),
                          ),
                        if (!showTrash && onEdit != null)
                          IconButton(
                            tooltip: 'Изменить',
                            icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurface),
                            onPressed: () => onEdit!(record),
                          ),
                        IconButton(
                          tooltip: showTrash ? 'Удалить навсегда' : 'Удалить',
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                          onPressed: () => onDelete(record),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('SKU: ${record['sku'] ?? '—'}', style: TextStyle(fontSize: 12, color: cs.onSurface)),
                if ((record['barcode'] ?? '').toString().isNotEmpty)
                  Text(record['barcode'].toString(), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('Остаток общий: $total $ul', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text('Склад: $whQty $ul', style: TextStyle(fontSize: 13, color: cs.onSurface)),
                if (warehouseOutlets.isEmpty)
                  Text('—', style: TextStyle(color: cs.onSurfaceVariant))
                else if (hasStoreQty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: warehouseOutlets.map((o) {
                      final nm = (o['name'] ?? '').toString();
                      final q = summaryByName[nm] ?? 0;
                      return _MiniTag('$nm: ${q.toStringAsFixed(q % 1 == 0 ? 0 : 2)}', cs, processing: true);
                    }).toList(),
                  )
                else
                  Text('—', style: TextStyle(color: cs.onSurfaceVariant)),
                if (!showTrash && whQty > 0 && onDistribute != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => onDistribute!(record),
                    child: const Text('Распределить (шт)'),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  (record['warehouse_name'] ?? '').toString().isEmpty
                      ? 'Склад: —'
                      : 'Склад (имя): ${record['warehouse_name']}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'закупка: ${hasPurchase ? '${totalTjs.toStringAsFixed(2)} TJS / ≈ ${totalUsd.toStringAsFixed(2)} USD' : '—'}',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      Text(
                        'закупка (1 шт): ${lastPrice > 0 ? '${costTjs.toStringAsFixed(2)} TJS / ≈ ${costUsd.toStringAsFixed(2)} USD' : '—'}',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      Text(
                        'продажа: ${saleTjs.toStringAsFixed(2)} TJS / ≈ ${saleUsd.toStringAsFixed(2)} USD',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text, this.cs, {this.blue = false, this.purple = false, this.processing = false});
  final String text;
  final ColorScheme cs;
  final bool blue;
  final bool purple;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (processing) {
      bg = const Color(0xFF2563EB).withValues(alpha: 0.2);
      fg = cs.onSurface;
    } else if (blue) {
      bg = Colors.blue.withValues(alpha: 0.2);
      fg = cs.onSurface;
    } else if (purple) {
      bg = Colors.purple.withValues(alpha: 0.2);
      fg = cs.onSurface;
    } else {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppShape.br),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final whQty = _asDouble(widget.record['quantity']) ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1220) : Colors.white,
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
            const SizedBox(height: 14),
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
    required this.nameCtrl,
    required this.salePriceCtrl,
    required this.qtyCtrl,
    required this.usdToTjs,
    required this.api,
    required this.onSaved,
    required this.onError,
  });

  final int productId;
  final TextEditingController nameCtrl;
  final TextEditingController salePriceCtrl;
  final TextEditingController qtyCtrl;
  final double usdToTjs;
  final ApiClient api;
  final Future<void> Function() onSaved;
  final void Function(String) onError;

  @override
  State<_EditProductBottomSheet> createState() => _EditProductBottomSheetState();
}

class _EditProductBottomSheetState extends State<_EditProductBottomSheet> {
  bool _loading = false;

  Future<void> _save() async {
    final name = widget.nameCtrl.text.trim();
    if (name.isEmpty) {
      widget.onError('Введите название');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await widget.api.patch(
        'inventory/products/${widget.productId}/',
        body: {
          'name': name,
          'sale_price': double.tryParse(widget.salePriceCtrl.text.replaceAll(',', '.')) ?? 0,
          'quantity': double.tryParse(widget.qtyCtrl.text.replaceAll(',', '.')) ?? 0,
        },
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
    final sale = double.tryParse(widget.salePriceCtrl.text.replaceAll(',', '.')) ?? 0;
    final usd = widget.usdToTjs > 0 ? (sale / widget.usdToTjs).toStringAsFixed(2) : '—';

    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1220) : Colors.white,
        borderRadius: AppShape.sheetTop,
      ),
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Изменить товар', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 14),
          TextField(controller: widget.nameCtrl, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 10),
          TextField(
            controller: widget.salePriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Цена продажи (TJS)', suffixText: 'TJS'),
          ),
          Text(
            '≈ $usd USD (курс 1 USD = ${widget.usdToTjs.toStringAsFixed(2)} TJS)',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: widget.qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Остаток'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _save,
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
