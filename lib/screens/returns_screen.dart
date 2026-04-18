import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<Map<String, dynamic>> outlets = const [];
  List<Map<String, dynamic>> rows = const [];
  bool loadingOutlets = false;
  bool loading = false;

  int? filterOutletId;
  DateTimeRange? dateRange;
  String search = '';
  bool showTrash = false;
  int? deletingId;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadOutlets();
      await _load();
    });
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

  Future<void> _loadOutlets() async {
    final u = _user;
    if (u == null) return;
    setState(() => loadingOutlets = true);
    try {
      final api = context.read<ApiClient>();
      final wh = u['warehouse'];
      final role = u['role'] as String?;
      final qs = (wh != null && role != 'platform') ? '?warehouse=$wh' : '';
      final res = await api.get('inventory/outlets$qs');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          outlets = items;
          if (role == 'seller' && items.length == 1) {
            final id = _asInt(items.first['id']);
            if (id != null) filterOutletId = id;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => outlets = const []);
    } finally {
      if (mounted) setState(() => loadingOutlets = false);
    }
  }

  Future<void> _load() async {
    if (_user == null) {
      setState(() => rows = const []);
      return;
    }
    setState(() => loading = true);
    try {
      final qp = <String, String>{};
      if (filterOutletId != null) qp['outlet'] = filterOutletId.toString();
      if (search.trim().isNotEmpty) qp['search'] = search.trim();
      if (dateRange != null) {
        qp['date_from'] = _fmtYmd(dateRange!.start);
        qp['date_to'] = _fmtYmd(dateRange!.end);
      }
      if (showTrash) qp['trash'] = '1';
      final path = qp.isEmpty ? 'inventory/returns/' : 'inventory/returns/?${Uri(queryParameters: qp).query}';
      final api = context.read<ApiClient>();
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => rows = items);
      } else {
        setState(() => rows = const []);
      }
    } catch (_) {
      if (mounted) setState(() => rows = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _onDelete(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    final isTrash = showTrash;
    final product = (record['sale_product_name'] ?? '—').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTrash ? 'Удалить возврат навсегда?' : 'Переместить возврат в корзину?'),
        content: Text(
          isTrash
              ? 'Остаток будет снова списан из магазина. Запись удалится безвозвратно.'
              : 'Возврат «$product» будет перемещён в корзину.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isTrash ? 'Удалить навсегда' : 'В корзину'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => deletingId = id);
    try {
      final api = context.read<ApiClient>();
      final path = isTrash ? 'inventory/returns/$id/?force=1' : 'inventory/returns/$id/';
      final res = await api.delete(path);
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Не удалось удалить');
      _snack(isTrash ? 'Возврат удалён навсегда' : 'Возврат в корзине');
      await _load();
    } catch (_) {
      _snack('Не удалось удалить', error: true);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  Future<void> _onRestore(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('inventory/returns/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception();
      _snack('Возврат восстановлен');
      await _load();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  Future<void> _openFilters() async {
    final u = _user ?? const <String, dynamic>{};
    final allowOutletClear = (u['role'] as String?) != 'seller' || outlets.length > 1;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReturnsFilterSheet(
        outlets: outlets,
        allowOutletClear: allowOutletClear,
        outletId: filterOutletId,
        range: dateRange,
        showTrash: showTrash,
        onApply: (outlet, range, trash) {
          setState(() {
            filterOutletId = outlet;
            dateRange = range;
            showTrash = trash;
          });
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'returns', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadOutlets();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Text('Возвраты', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              _ReturnsCard(
                dark: dark,
                cs: cs,
                title: 'Возврат товаров',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Поиск по товару (название, модель, марка, штрихкод)',
                            ),
                            onChanged: (v) => search = v,
                            onSubmitted: (_) => _load(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Фильтры',
                          onPressed: _openFilters,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                        IconButton(
                          tooltip: 'Обновить',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (loadingOutlets)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Загрузка магазинов…', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                    const SizedBox(height: 10),
                    if (loading) const SkeletonListBlock(rows: 5)
else
                      _ReturnsTable(
                        cs: cs,
                        rows: rows,
                        showTrash: showTrash,
                        deletingId: deletingId,
                        onDelete: _onDelete,
                        onRestore: _onRestore,
                      ),
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

class _ReturnsCard extends StatelessWidget {
  const _ReturnsCard({required this.dark, required this.cs, required this.title, required this.child});
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

class _ReturnsTable extends StatelessWidget {
  const _ReturnsTable({
    required this.cs,
    required this.rows,
    required this.showTrash,
    required this.deletingId,
    required this.onDelete,
    required this.onRestore,
  });

  final ColorScheme cs;
  final List<Map<String, dynamic>> rows;
  final bool showTrash;
  final int? deletingId;
  final void Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onRestore;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Нет возвратов', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 11),
        dataTextStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 11),
        columnSpacing: 12,
        columns: const [
          DataColumn(label: Text('Дата')),
          DataColumn(label: Text('Магазин')),
          DataColumn(label: Text('Товар')),
          DataColumn(label: Text('Прод.')),
          DataColumn(label: Text('Возвр.')),
          DataColumn(label: Text('Причина')),
          DataColumn(label: Text('Создано')),
          DataColumn(label: Text('')),
        ],
        rows: rows.take(50).map((r) {
          final returned = (r['returned_at'] ?? '').toString();
          final outlet = (r['sale_outlet_name'] ?? '—').toString();
          final prod = (r['sale_product_name'] ?? '—').toString();
          final sq = r['sale_quantity'];
          final rq = r['quantity_returned'];
          final reason = (r['reason'] ?? '—').toString();
          final created = (r['created_at'] ?? '').toString().replaceFirst('T', ' ');
          final createdShort = created.isEmpty ? '—' : created.substring(0, created.length.clamp(0, 19));
          return DataRow(
            cells: [
              DataCell(Text(returned.isEmpty ? '—' : returned.substring(0, returned.length.clamp(0, 10)))),
              DataCell(SizedBox(width: 100, child: Text(outlet, overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(width: 180, child: Text(prod, overflow: TextOverflow.ellipsis))),
              DataCell(Text(sq?.toString() ?? '—')),
              DataCell(Text(rq?.toString() ?? '—')),
              DataCell(SizedBox(width: 120, child: Text(reason == '' ? '—' : reason, overflow: TextOverflow.ellipsis))),
              DataCell(Text(createdShort)),
              DataCell(
                showTrash
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Восстановить',
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            onPressed: () => onRestore(r),
                          ),
                          IconButton(
                            tooltip: 'Удалить навсегда',
                            icon: deletingId == _asInt(r['id'])
                                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                                : const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                            onPressed: deletingId == _asInt(r['id']) ? null : () => onDelete(r),
                          ),
                        ],
                      )
                    : IconButton(
                        tooltip: 'Удалить',
                        icon: deletingId == _asInt(r['id'])
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                            : const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        onPressed: deletingId == _asInt(r['id']) ? null : () => onDelete(r),
                      ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ReturnsFilterSheet extends StatefulWidget {
  const _ReturnsFilterSheet({
    required this.outlets,
    required this.allowOutletClear,
    required this.outletId,
    required this.range,
    required this.showTrash,
    required this.onApply,
  });

  final List<Map<String, dynamic>> outlets;
  final bool allowOutletClear;
  final int? outletId;
  final DateTimeRange? range;
  final bool showTrash;
  final void Function(int? outletId, DateTimeRange? range, bool showTrash) onApply;

  @override
  State<_ReturnsFilterSheet> createState() => _ReturnsFilterSheetState();
}

class _ReturnsFilterSheetState extends State<_ReturnsFilterSheet> {
  int? outletId;
  DateTimeRange? range;
  bool trash = false;

  @override
  void initState() {
    super.initState();
    outletId = widget.outletId;
    range = widget.range;
    trash = widget.showTrash;
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
      padding: EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 14 + MediaQuery.of(context).viewInsets.bottom),
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
            DropdownButtonFormField<int>(
              key: ValueKey<int?>(outletId),
              initialValue: outletId,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, labelText: 'Магазин (все)'),
              items: [
                if (widget.allowOutletClear) const DropdownMenuItem<int>(value: null, child: Text('Все магазины')),
                ...widget.outlets.map((o) {
                  final id = _asInt(o['id']);
                  final name = (o['name'] ?? '').toString().trim();
                  if (id == null) return null;
                  return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
                }).whereType<DropdownMenuItem<int>>(),
              ],
              onChanged: (v) => setState(() => outletId = v),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: range,
                );
                if (picked != null) setState(() => range = picked);
              },
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(range == null ? 'Дата от — Дата до' : '${_fmtYmd(range!.start)} — ${_fmtYmd(range!.end)}'),
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
                widget.onApply(outletId, range, trash);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

String _fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
