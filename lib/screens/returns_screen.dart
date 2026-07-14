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
import '../widgets/quick_date_range_chips.dart';
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
  String? historyPreset = 'month';
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
      setState(() {
        historyPreset = 'month';
        dateRange = _historyRangeForPreset('month');
      });
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
    setState(() {
      historyPreset = 'custom';
      dateRange = picked;
    });
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
        return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
      default:
        return DateTimeRange(start: today.subtract(const Duration(days: 30)), end: today);
    }
  }

  void _applyHistoryPreset(String key) {
    setState(() {
      historyPreset = key;
      dateRange = _historyRangeForPreset(key);
      historyPage = 1;
    });
  }

  void _applyHistoryFilters() {
    search = historySearchCtrl.text;
    setState(() => historyPage = 1);
    _load();
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
              Text('Возвраты', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.25)),
              const SizedBox(height: 10),
              _ReturnsCard(
                title: 'Оформить возврат',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: scanCtrl,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                hintText: 'Сканируйте штрих-код или IMEI...',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onSubmitted: _onScanSale,
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: () => _onScanSale(scanCtrl.text),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                              ),
                              child: const Text('Скан', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: saleSearchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Поиск продажи по товару',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded, size: 20),
                          onPressed: _loadSales,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (_) => _loadSales(),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey<int?>(filterOutletId),
                      initialValue: filterOutletId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Все магазины',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
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
                    const SizedBox(height: 8),
                    if (salesLoading)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
                    else if (sales.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Нет продаж за 30 дней', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    else ...[
                      _SalesHeaderCard(cs: cs, dark: dark),
                      for (final s in salesSlice) _SalesReturnCard(record: s, cs: cs, dark: dark, onReturn: () => _openReturnModal(s)),
                      if (sales.length > _salesPageSize)
                        _Pager(
                          page: salesPage,
                          hasMore: salesPage * _salesPageSize < sales.length,
                          onPrev: salesPage > 1 ? () => setState(() => salesPage--) : null,
                          onNext: salesPage * _salesPageSize < sales.length ? () => setState(() => salesPage++) : null,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ReturnsCard(
                title: 'История возвратов',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: historySearchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Поиск по товару',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (v) => search = v,
                      onSubmitted: (_) => _applyHistoryFilters(),
                    ),
                    const SizedBox(height: 8),
                    QuickDateRangeChips(
                      colorScheme: cs,
                      selected: historyPreset == 'custom' ? null : historyPreset,
                      showPeriod: false,
                      onToday: () => _applyHistoryPreset('today'),
                      onWeek: () => _applyHistoryPreset('week'),
                      onMonth: () => _applyHistoryPreset('month'),
                      onPeriod: _pickHistoryRange,
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _pickHistoryRange,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dateRange != null ? '${_fmtYmd(dateRange!.start)} → ${_fmtYmd(dateRange!.end)}' : 'Начальная дата → Конечная дата',
                                  style: TextStyle(fontSize: 13, color: dateRange != null ? cs.onSurface : cs.onSurfaceVariant),
                                ),
                              ),
                              Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey<String>('hist-$filterOutletId'),
                      initialValue: filterOutletId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Все магазины',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
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
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Switch(value: showTrash, onChanged: (v) => setState(() => showTrash = v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        const SizedBox(width: 8),
                        Text('В корзине', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _applyHistoryFilters,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        label: const Text('Применить', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                          hasMore: historyPage * _historyPageSize < rows.length,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark ? AppBrand.darkCard : cs.surface,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SalesHeaderCard extends StatelessWidget {
  const _SalesHeaderCard({required this.cs, required this.dark});
  final ColorScheme cs;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withValues(alpha: 0.85));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? AppBrand.darkRow : cs.surfaceContainer,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(flex: 10, child: Text('Дата', style: h)),
          Expanded(flex: 12, child: Text('Магазин', style: h)),
          Expanded(flex: 6, child: Text('Кол-во', style: h, textAlign: TextAlign.right)),
          const SizedBox(width: 88),
        ],
      ),
    );
  }
}

class _SalesReturnCard extends StatelessWidget {
  const _SalesReturnCard({required this.record, required this.cs, required this.dark, required this.onReturn});
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
    final product = (record['product_name'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? AppBrand.darkRow : cs.surfaceContainer,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 10,
                child: Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              Expanded(
                flex: 12,
                child: Text(
                  (record['outlet_name'] ?? '—').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                ),
              ),
              Expanded(
                flex: 6,
                child: Text(_fmtQty(sold), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: ret >= sold
                    ? Text('Возвращено', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
                    : SizedBox(
                        height: 28,
                        child: FilledButton(
                          onPressed: onReturn,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Вернуть', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
              ),
            ],
          ),
          if (product.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(product, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
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
                Text(prod, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(
                  '$date · $outlet · возврат: ${rq ?? '—'}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (showTrash)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onRestore,
              icon: const Icon(Icons.undo_rounded, size: 20),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: deleting ? null : onDelete,
            icon: deleting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.hasMore, required this.onPrev, required this.onNext});
  final int page;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
              border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
            ),
            child: Text('Стр. $page', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: hasMore ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
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
