import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_brand.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../utils/product_scan_utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _salesPageSize = 8;
const _historyPageSize = 15;

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<Map<String, dynamic>> outlets = const [];
  List<Map<String, dynamic>> rows = const [];
  List<Map<String, dynamic>> sales = const [];

  bool loadingOutlets = false;
  bool loading = false;
  bool salesLoading = false;

  int? filterOutletId;
  DateTimeRange? dateRange;
  String search = '';
  String saleSearch = '';
  bool showTrash = false;
  int? deletingId;

  int salesPage = 1;
  int historyPage = 1;

  final TextEditingController scanCtrl = TextEditingController();
  final TextEditingController saleSearchCtrl = TextEditingController();
  final TextEditingController historySearchCtrl = TextEditingController();
  Timer? _saleSearchDebounce;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  @override
  void initState() {
    super.initState();
    saleSearchCtrl.addListener(_onSaleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadOutlets();
      await _load();
      await _loadSales();
    });
  }

  void _onSaleSearchChanged() {
    final v = saleSearchCtrl.text;
    if (v == saleSearch) return;
    saleSearch = v;
    _saleSearchDebounce?.cancel();
    _saleSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _loadSales();
    });
  }

  @override
  void dispose() {
    _saleSearchDebounce?.cancel();
    scanCtrl.dispose();
    saleSearchCtrl.dispose();
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
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          rows = items;
          historyPage = 1;
        });
      } else {
        setState(() => rows = const []);
      }
    } catch (_) {
      if (mounted) setState(() => rows = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadSales() async {
    if (_user == null) return;
    setState(() => salesLoading = true);
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final qp = <String, String>{
        'date_from': _fmtYmd(from),
        'date_to': _fmtYmd(now),
      };
      if (filterOutletId != null) qp['outlet'] = filterOutletId.toString();
      if (saleSearch.trim().isNotEmpty) qp['search'] = saleSearch.trim();
      final res = await context.read<ApiClient>().get('inventory/sales/?${Uri(queryParameters: qp).query}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() {
          sales = items;
          salesPage = 1;
        });
      } else {
        setState(() => sales = const []);
      }
    } catch (_) {
      if (mounted) setState(() => sales = const []);
    } finally {
      if (mounted) setState(() => salesLoading = false);
    }
  }

  Map<String, dynamic>? _findSaleByCode(String raw) {
    final norm = normalizeScanCode(raw).toLowerCase();
    if (norm.isEmpty) return null;
    for (final s in sales) {
      final barcode = (s['product_barcode'] ?? '').toString().trim().toLowerCase();
      final sku = (s['product_sku'] ?? '').toString().trim().toLowerCase();
      if (barcode == norm || sku == norm) return s;
    }
    for (final s in sales) {
      final name = (s['product_name'] ?? '').toString().toLowerCase();
      if (name.contains(norm)) return s;
    }
    return null;
  }

  void _onScanSale(String raw) {
    final match = _findSaleByCode(raw);
    if (match != null) {
      _openReturnModal(match);
    } else {
      setState(() {
        saleSearch = normalizeScanCode(raw);
        saleSearchCtrl.text = saleSearch;
      });
      _loadSales();
      _snack('Продажа не найдена в списке — обновите поиск');
    }
  }

  Future<void> _openReturnModal(Map<String, dynamic> record) async {
    final sold = _asDouble(record['quantity']) ?? 0;
    final already = _asDouble(record['total_returned']) ?? 0;
    final maxReturnable = ((sold - already).clamp(0, sold)).toDouble();
    var qty = maxReturnable > 0 ? maxReturnable : 1.0;
    var returnedAt = DateTime.now();
    final reasonCtrl = TextEditingController();
    var submitting = false;

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
                    '${record['product_name'] ?? '—'} — ${record['outlet_name'] ?? '—'}, продано: ${_fmtQty(sold)}'
                    '${already > 0 ? ', возвращено: ${_fmtQty(already)}' : ''}',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Количество',
                      helperText: 'От 1 до ${_fmtQty(maxReturnable)}',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(text: _fmtQty(qty)),
                    onChanged: (v) => qty = double.tryParse(v.replaceAll(',', '.')) ?? qty,
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
                    decoration: const InputDecoration(isDense: true, labelText: 'Причина', hintText: 'Необязательно'),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: (submitting || qty <= 0 || qty > maxReturnable)
                          ? null
                          : () async {
                              setSheet(() => submitting = true);
                              try {
                                final res = await context.read<ApiClient>().post(
                                      'inventory/returns/',
                                      body: {
                                        'sale': record['id'],
                                        'quantity_returned': qty,
                                        'returned_at': _fmtYmd(returnedAt),
                                        'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                if (!ctx.mounted) return;
                                if (res.statusCode != 200 && res.statusCode != 201) {
                                  final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
                                  throw Exception(_apiError(data));
                                }
                                Navigator.pop(ctx);
                                _snack('Возврат оформлен');
                                await _load();
                                await _loadSales();
                              } catch (e) {
                                _snack(e.toString(), error: true);
                              } finally {
                                if (ctx.mounted) setSheet(() => submitting = false);
                              }
                            },
                      child: Text(submitting ? 'Оформление…' : 'Оформить возврат'),
                    ),
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
    if (ok != true || !mounted) return;
    setState(() => deletingId = id);
    try {
      final path = isTrash ? 'inventory/returns/$id/?force=1' : 'inventory/returns/$id/';
      final res = await context.read<ApiClient>().delete(path);
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception();
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
      final res = await context.read<ApiClient>().patch('inventory/returns/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception();
      _snack('Возврат восстановлен');
      await _load();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  Future<void> _pickHistoryRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() => dateRange = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'returns', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final allowOutletClear = u['role'] != 'seller' || outlets.length > 1;
    final salesSlice = sales.skip((salesPage - 1) * _salesPageSize).take(_salesPageSize).toList();
    final historySlice = rows.skip((historyPage - 1) * _historyPageSize).take(_historyPageSize).toList();

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadOutlets();
            await _load();
            await _loadSales();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            children: [
              Text('Возвраты', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.25)),
              const SizedBox(height: 10),
              _ReturnsCard(
                title: 'Оформить возврат',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: scanCtrl,
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.qr_code_2_rounded, size: 20),
                              hintText: 'Сканируйте штрих-код или IMEI...',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onSubmitted: _onScanSale,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton(
                            onPressed: () => _onScanSale(scanCtrl.text),
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Icon(Icons.center_focus_weak_rounded, size: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: saleSearchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        hintText: 'Поиск продажи по товару',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded, size: 20),
                          onPressed: _loadSales,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (_) => _loadSales(),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      key: ValueKey<int?>(filterOutletId),
                      initialValue: filterOutletId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, labelText: 'Магазин', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      items: [
                        if (allowOutletClear) const DropdownMenuItem<int>(value: null, child: Text('Все магазины')),
                        ...outlets.map((o) {
                          final id = _asInt(o['id']);
                          if (id == null) return null;
                          final name = (o['name'] ?? '').toString().trim();
                          return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
                        }).whereType<DropdownMenuItem<int>>(),
                      ],
                      onChanged: (v) {
                        setState(() => filterOutletId = v);
                        _loadSales();
                        _load();
                      },
                    ),
                    const SizedBox(height: 10),
                    if (salesLoading)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
                    else if (sales.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Нет продаж за 30 дней', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    else ...[
                      _SalesTableHeader(cs: cs, dark: dark),
                      for (final s in salesSlice) _SalesTableRow(record: s, cs: cs, dark: dark, onReturn: () => _openReturnModal(s)),
                      if (sales.length > _salesPageSize) _Pager(page: salesPage, total: (sales.length / _salesPageSize).ceil(), onPrev: salesPage > 1 ? () => setState(() => salesPage--) : null, onNext: salesPage * _salesPageSize < sales.length ? () => setState(() => salesPage++) : null),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _ReturnsCard(
                title: 'История возвратов',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: historySearchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Поиск по товару',
                        suffixIcon: IconButton(icon: const Icon(Icons.search_rounded, size: 20), onPressed: () { search = historySearchCtrl.text; _load(); }),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (v) => search = v,
                      onSubmitted: (_) => _load(),
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
                              Expanded(child: Text(dateRange != null ? _fmtYmd(dateRange!.start) : 'Дата от', style: TextStyle(fontSize: 13, color: dateRange != null ? cs.onSurface : cs.onSurfaceVariant))),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: cs.onSurfaceVariant),
                              Expanded(child: Text(dateRange != null ? _fmtYmd(dateRange!.end) : 'Дата до', textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: dateRange != null ? cs.onSurface : cs.onSurfaceVariant))),
                              const SizedBox(width: 8),
                              Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (dateRange != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () { setState(() => dateRange = null); _load(); }, child: const Text('Сбросить даты')),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey<String>('hist-$filterOutletId'),
                      initialValue: filterOutletId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, labelText: 'Магазин (все)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      items: [
                        if (allowOutletClear) const DropdownMenuItem<int>(value: null, child: Text('Все магазины')),
                        ...outlets.map((o) {
                          final id = _asInt(o['id']);
                          if (id == null) return null;
                          final name = (o['name'] ?? '').toString().trim();
                          return DropdownMenuItem<int>(value: id, child: Text(name.isEmpty ? 'Магазин $id' : name, overflow: TextOverflow.ellipsis));
                        }).whereType<DropdownMenuItem<int>>(),
                      ],
                      onChanged: (v) {
                        setState(() => filterOutletId = v);
                        _load();
                        _loadSales();
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Switch(value: showTrash, onChanged: (v) { setState(() => showTrash = v); _load(); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        const SizedBox(width: 8),
                        Text('В корзине', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const SkeletonListBlock(rows: 4)
                    else if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Нет возвратов', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    else ...[
                      for (final r in historySlice)
                        _HistoryRow(
                          record: r,
                          cs: cs,
                          dark: dark,
                          showTrash: showTrash,
                          deleting: deletingId == _asInt(r['id']),
                          onDelete: () => _onDelete(r),
                          onRestore: () => _onRestore(r),
                        ),
                      if (rows.length > _historyPageSize)
                        _Pager(
                          page: historyPage,
                          total: (rows.length / _historyPageSize).ceil(),
                          onPrev: historyPage > 1 ? () => setState(() => historyPage--) : null,
                          onNext: historyPage * _historyPageSize < rows.length ? () => setState(() => historyPage++) : null,
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

class _ReturnsCard extends StatelessWidget {
  const _ReturnsCard({required this.title, required this.child});
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

class _SalesTableHeader extends StatelessWidget {
  const _SalesTableHeader({required this.cs, required this.dark});
  final ColorScheme cs;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    TextStyle h = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)))),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Дата', style: h)),
          Expanded(flex: 4, child: Text('Магазин', style: h)),
          Expanded(flex: 2, child: Text('Кол-во', style: h, textAlign: TextAlign.right)),
          const SizedBox(width: 88),
        ],
      ),
    );
  }
}

class _SalesTableRow extends StatelessWidget {
  const _SalesTableRow({required this.record, required this.cs, required this.dark, required this.onReturn});
  final Map<String, dynamic> record;
  final ColorScheme cs;
  final bool dark;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final sold = _asDouble(record['quantity']) ?? 0;
    final ret = _asDouble(record['total_returned']) ?? 0;
    final soldAt = (record['sold_at'] ?? '').toString();
    final date = soldAt.isEmpty ? '—' : soldAt.substring(0, soldAt.length.clamp(0, 10));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)))),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(date, style: TextStyle(fontSize: 12, color: cs.onSurface))),
          Expanded(flex: 4, child: Text((record['outlet_name'] ?? '—').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface))),
          Expanded(flex: 2, child: Text(_fmtQty(sold), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: cs.onSurface))),
          SizedBox(
            width: 88,
            child: ret >= sold
                ? Text('Возвращено', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
                : Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onReturn,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Вернуть', style: TextStyle(fontSize: 12)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.cs, required this.dark, required this.showTrash, required this.deleting, required this.onDelete, required this.onRestore});
  final Map<String, dynamic> record;
  final ColorScheme cs;
  final bool dark;
  final bool showTrash;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final returned = (record['returned_at'] ?? '').toString();
    final date = returned.isEmpty ? '—' : returned.substring(0, returned.length.clamp(0, 10));
    final outlet = (record['sale_outlet_name'] ?? '—').toString();
    final prod = (record['sale_product_name'] ?? '—').toString();
    final rq = record['quantity_returned'];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? AppBrand.darkRow : cs.surfaceContainer,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prod, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text('$date · $outlet', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                Text('возврат: ${rq ?? '—'}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (showTrash) ...[
            IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), onPressed: onRestore, icon: const Icon(Icons.undo_rounded, size: 20)),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: deleting ? null : onDelete,
              icon: deleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
            ),
          ] else
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: deleting ? null : onDelete,
              icon: deleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
            ),
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

String _apiError(dynamic data) {
  if (data is! Map) return 'Ошибка';
  final q = data['quantity_returned'];
  if (q is List && q.isNotEmpty) return q.first.toString();
  final d = data['detail'];
  if (d is String) return d;
  return 'Не удалось оформить возврат';
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

String _fmtQty(double v) {
  return v.toStringAsFixed(v % 1 == 0 ? 0 : 3);
}
