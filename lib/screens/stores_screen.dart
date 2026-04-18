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

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

String _fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _formatMoneyRu(double n) {
  final neg = n < 0;
  final abs = neg ? -n : n;
  final s = abs.toStringAsFixed(2);
  final dot = s.indexOf('.');
  final intPart = s.substring(0, dot);
  final dec = s.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('\u00A0');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}${buf.toString()}$dec';
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

  String? selectedOutletKey; // 'all' or outlet id string

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
        setState(() => products = arrays.expand((x) => x).toList());
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
            setState(() => products = list);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => products = const []);
    } finally {
      if (mounted) setState(() => loading = false);
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

  Future<void> _openSale({int? presetProductId}) async {
    if (selectedOutletKey == null || _showAllOutlets) return;
    final oid = int.tryParse(selectedOutletKey!);
    if (oid == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _RecordSaleSheet(
        outletId: oid,
        products: products,
        presetProductId: presetProductId,
        onSaved: () {
          Navigator.pop(ctx);
          _loadProducts();
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

  Widget _productCard(Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;

    final outletName = (r['outlet_name'] ?? '').toString();
    final name = (r['product_name'] ?? r['name'] ?? '—').toString();
    final sub = _productSubline(r);
    final sku = (r['sku'] ?? '—').toString();

    final qty = _asDouble(r['quantity']) ?? 0;
    final unit = _unitLabel((r['unit'] ?? 'pcs').toString());

    final tjs = _asDouble(r['total_purchase_tjs']) ?? 0;
    final usdPur = _asDouble(r['total_purchase_usd']) ?? 0;
    final totalTjs = tjs + usdPur * usdToTjs;
    final totalUsd = usdToTjs > 0 ? totalTjs / usdToTjs : 0.0;

    final salePrice = _asDouble(r['sale_price']) ?? 0;

    final transferAt = (r['transfer_date'] ?? '').toString();
    final saleDates = (r['sale_dates'] is List) ? (r['sale_dates'] as List).map((x) => x.toString()).toList() : <String>[];

    final hasStockId = _asInt(r['outlet_stock_id']) != null;

    const compactConstraints = BoxConstraints.tightFor(width: 36, height: 36);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showAllOutlets) ...[
              Text(outletName.isEmpty ? '—' : outletName, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('Артикул: $sku', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 0,
                  children: [
                    if (!showTrash && !_showAllOutlets)
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        tooltip: 'Оформить продажу',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: compactConstraints,
                        onPressed: () => _openSale(presetProductId: _asInt(r['product_id'])),
                      ),
                    if (showTrash && hasStockId)
                      IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: 'Восстановить',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: compactConstraints,
                        onPressed: () => _restoreStock(r),
                      ),
                    if (!showTrash && hasStockId)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Изменить',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: compactConstraints,
                        onPressed: () => _openEditStock(r),
                      ),
                    if (hasStockId)
                      IconButton(
                        icon: Icon(showTrash ? Icons.delete_forever : Icons.delete_outline),
                        tooltip: showTrash ? 'Удалить навсегда' : 'Удалить',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: compactConstraints,
                        onPressed: () => _deleteStock(r),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _kv('Кол-во', '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 3)} $unit', cs),
                _kv('Закупка (пул)', '${_formatMoneyRu(totalTjs)} TJS\n≈ ${_formatMoneyRu(totalUsd)} USD', cs),
                _kv('Цена продажи', _formatMoneyRu(salePrice), cs),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Дата поступления: ${transferAt.isEmpty ? '—' : transferAt.replaceFirst('T', ' ')}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text('Даты продаж:', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            if (saleDates.isEmpty)
              Text('—', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in saleDates.take(5))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(d, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ),
                  if (saleDates.length > 5)
                    Text('+${saleDates.length - 5}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, ColorScheme cs) {
    final lines = v.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        for (final l in lines) Text(l, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'stores', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final outletItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: 'all', child: Text('Все магазины')),
      for (final o in outlets)
        if (_asInt(o['id']) != null)
          DropdownMenuItem<String>(
            value: _asInt(o['id'])!.toString(),
            child: Text((o['name'] ?? 'Магазин ${o['id']}').toString()),
          ),
    ];

    final emptyText = selectedOutletKey == null
        ? 'Выберите магазин'
        : (_showAllOutlets ? 'Нет товаров в магазинах' : 'В магазине нет товаров');

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('Магазин — остатки по магазинам', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _openAddOutlet,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить магазин'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              value: selectedOutletKey,
                              decoration: const InputDecoration(labelText: 'Магазин', border: OutlineInputBorder()),
                              items: outletItems,
                              onChanged: (v) {
                                setState(() => selectedOutletKey = v);
                                _loadProducts();
                              },
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: showTrash,
                                onChanged: (v) {
                                  setState(() => showTrash = v);
                                  _loadProducts();
                                },
                              ),
                              Text('В корзине', style: TextStyle(color: cs.onSurfaceVariant)),
                            ],
                          ),
                          if (selectedOutletKey != null && !_showAllOutlets && !showTrash)
                            OutlinedButton(
                              onPressed: () => _openSale(),
                              child: const Text('Оформить продажу'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (loading)
                const SkeletonListBlock(rows: 6)
else if (products.isEmpty)
                Text(emptyText, style: TextStyle(color: cs.onSurfaceVariant))
              else
                ...products.map(_productCard),
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

class _RecordSaleSheet extends StatefulWidget {
  const _RecordSaleSheet({
    required this.outletId,
    required this.products,
    required this.onSaved,
    this.presetProductId,
  });

  final int outletId;
  final List<Map<String, dynamic>> products;
  final int? presetProductId;
  final VoidCallback onSaved;

  @override
  State<_RecordSaleSheet> createState() => _RecordSaleSheetState();
}

class _RecordSaleSheetState extends State<_RecordSaleSheet> {
  int? productId;
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  String currency = 'TJS';
  DateTime soldAt = DateTime.now();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    productId = widget.presetProductId;
  }

  @override
  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSoldAt() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDate: soldAt,
    );
    if (d == null || !mounted) return;
    setState(() => soldAt = d);
  }

  Future<void> _save() async {
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите товар')));
      return;
    }
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите количество')));
      return;
    }
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите цену')));
      return;
    }

    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/sales/',
        body: {
          'outlet': widget.outletId,
          'product': productId,
          'quantity': qty,
          'unit_price': price,
          'currency': currency,
          'sold_at': _fmtYmd(soldAt),
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(_firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Продажа оформлена')));
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

    final items = <DropdownMenuItem<int>>[
      for (final p in widget.products)
        if (_asInt(p['product_id']) != null)
          DropdownMenuItem<int>(
            value: _asInt(p['product_id'])!,
            child: Text('${(p['product_name'] ?? 'Товар').toString()} (${(p['sku'] ?? '').toString()})'),
          ),
    ];

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Оформить продажу', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: productId,
              decoration: const InputDecoration(labelText: 'Товар', border: OutlineInputBorder()),
              items: items,
              onChanged: (v) => setState(() => productId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Количество', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Цена за единицу', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: currency,
              decoration: const InputDecoration(labelText: 'Валюта', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'TJS', child: Text('TJS')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
              ],
              onChanged: (v) => setState(() => currency = v ?? 'TJS'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата продажи'),
              subtitle: Text(_fmtYmd(soldAt)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickSoldAt,
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

