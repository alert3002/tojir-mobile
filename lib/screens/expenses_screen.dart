import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _expensesMobilePageSize = 10;
const _cardBg = Color(0xFF1A2438);
const _amountRed = Color(0xFFFF7875);
const _blue = Color(0xFF2563EB);

double? _parseMoneyNumber(dynamic v) {
  if (v == null || v == '') return null;
  final t = v.toString().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  return double.tryParse(t);
}

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
  for (final key in ['amount', 'outlet', 'category', 'note']) {
    final v = m[key];
    if (v is List && v.isNotEmpty) return v.first.toString();
  }
  return 'Ошибка';
}

String _fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget? _fxLine(dynamic amount, String? currency, double? usdToTjs, ColorScheme cs) {
  final cur = (currency ?? '').trim().toUpperCase();
  final n = amount is num && amount.isFinite ? amount.toDouble() : _parseMoneyNumber(amount);
  final rate = usdToTjs;
  if (n == null || n == 0 || rate == null || rate <= 0) return null;
  if (cur == 'TJS') {
    return Text(
      '≈ ${_formatMoneyRu(n / rate)} USD',
      style: TextStyle(fontSize: 11, height: 1.35, color: cs.onSurfaceVariant),
    );
  }
  if (cur == 'USD') {
    return Text(
      '≈ ${_formatMoneyRu(n * rate)} TJS',
      style: TextStyle(fontSize: 11, height: 1.35, color: cs.onSurfaceVariant),
    );
  }
  return null;
}

String _formatExpenseDate(dynamic v) {
  if (v == null) return '—';
  final s = v.toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> rows = const [];
  bool loading = false;

  final TextEditingController searchCtrl = TextEditingController();
  String search = '';

  DateTimeRange? dateRange;

  bool showTrash = false;

  List<Map<String, dynamic>> warehouses = const [];
  int? warehouseFilter;

  List<Map<String, dynamic>> outlets = const [];
  double? usdToTjs;

  int? deletingId;
  int mobilePage = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      await _loadWarehouses();
      await _loadOutlets();
      await _load();
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _loadRate() async {
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => usdToTjs = null);
        return;
      }
      final d = _tryJsonMap(res.body);
      final n = _asDouble(d['usd_to_tjs']);
      setState(() => usdToTjs = (n != null && n.isFinite && n > 0) ? n : null);
    } catch (_) {
      if (mounted) setState(() => usdToTjs = null);
    }
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
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/outlets');
      if (!mounted) return;
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

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() => loading = true);
    try {
      final q = <String, String>{};
      final s = search.trim();
      if (s.isNotEmpty) q['search'] = s;
      if (warehouseFilter != null) q['warehouse'] = warehouseFilter.toString();
      if (dateRange != null) {
        q['date_from'] = _fmtYmd(dateRange!.start);
        q['date_to'] = _fmtYmd(dateRange!.end);
      }
      if (showTrash) q['trash'] = '1';
      final qs = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final path = 'inventory/expenses/${qs.isEmpty ? '' : '?$qs'}';

      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла или вход недействителен. Войдите снова.');
        setState(() {
          rows = const [];
          loading = false;
        });
        return;
      }
      if (res.statusCode != 200) {
        setState(() => rows = const []);
        return;
      }

      final j = jsonDecode(res.body);
      final list = j is List
          ? j.cast<Map<String, dynamic>>()
          : (j is Map && j['results'] is List)
              ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
              : <Map<String, dynamic>>[];
      setState(() {
        rows = list;
        mobilePage = 1;
      });
    } catch (_) {
      if (mounted) setState(() => rows = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: 'Период',
      cancelText: 'Отмена',
      confirmText: 'ОК',
      locale: const Locale('ru'),
    );
    if (picked == null || !mounted) return;
    setState(() => dateRange = picked);
    await _load();
  }

  Future<void> _openAdd() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _AddExpenseSheet(
        outlets: outlets,
        usdToTjs: usdToTjs,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Future<void> _openEdit(Map<String, dynamic> record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _EditExpenseSheet(
        record: record,
        outlets: outlets,
        usdToTjs: usdToTjs,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> record, {required bool permanent}) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? 'Удалить расход навсегда?' : 'Переместить расход в корзину?'),
        content: Text(permanent ? 'Запись удалится безвозвратно.' : 'Расход будет перемещён в корзину.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(permanent ? 'Удалить навсегда' : 'В корзину'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => deletingId = id);
    try {
      final api = context.read<ApiClient>();
      final path = 'inventory/expenses/$id/${permanent ? '?force=1' : ''}';
      final res = await api.delete(path);
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) throw Exception();
      _snack(permanent ? 'Расход удалён навсегда' : 'Расход в корзине');
      await _load();
    } catch (_) {
      _snack('Не удалось удалить', error: true);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  Future<void> _restore(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('inventory/expenses/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception();
      _snack('Расход восстановлен');
      await _load();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  List<Map<String, dynamic>> get _mobileSlice {
    final start = (mobilePage - 1) * _expensesMobilePageSize;
    if (start >= rows.length) return const [];
    final end = (start + _expensesMobilePageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  Widget _actionsRow(Map<String, dynamic> r) {
    final id = _asInt(r['id']);
    const compact = BoxConstraints.tightFor(width: 36, height: 36);

    if (showTrash) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 20),
            tooltip: 'Восстановить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            color: Colors.white.withValues(alpha: 0.85),
            onPressed: () => _restore(r),
          ),
          IconButton(
            icon: deletingId == id
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_forever_rounded, size: 20, color: Color(0xFFFF4D4F)),
            tooltip: 'Удалить навсегда',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            onPressed: deletingId == id ? null : () => _delete(r, permanent: true),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Изменить',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compact,
          color: Colors.white.withValues(alpha: 0.85),
          onPressed: () => _openEdit(r),
        ),
        IconButton(
          icon: deletingId == id
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFFF4D4F)),
          tooltip: 'Удалить',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compact,
          onPressed: deletingId == id ? null : () => _delete(r, permanent: false),
        ),
      ],
    );
  }

  Widget _expenseMobileCard(Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    final cat = (r['category'] ?? '—').toString();
    final cur = (r['currency'] ?? 'TJS').toString();
    final amt = _asDouble(r['amount']);
    final note = (r['note'] ?? '').toString().trim();
    final outletName = (r['outlet_name'] ?? '').toString();
    final whName = (r['warehouse_name'] ?? '').toString();
    final storeLabel = outletName.isNotEmpty ? outletName : (whName.isNotEmpty ? 'Общий расход' : '—');

    final meta = [
      ('Дата', _formatExpenseDate(r['expense_date'])),
      ('Магазин', storeLabel),
      ('Склад', whName.isNotEmpty ? whName : '—'),
      ('Кто', (r['created_by_display'] ?? '—').toString()),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  cat,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _actionsRow(r),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF4D4F).withValues(alpha: 0.22)),
            ),
            child: amt != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_formatMoneyRu(amt)} $cur',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _amountRed, height: 1.25),
                      ),
                      if (_fxLine(amt, cur, usdToTjs, cs) != null) _fxLine(amt, cur, usdToTjs, cs)!,
                    ],
                  )
                : const Text('—', style: TextStyle(color: _amountRed)),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.4,
            children: [
              for (final (label, value) in meta)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92), height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(note, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.85), height: 1.35)),
            ),
          ],
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
    final totalPages = rows.isEmpty ? 1 : (rows.length / _expensesMobilePageSize).ceil();

    if (u == null || !canAccessSection(u, 'expenses', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadWarehouses();
            await _loadOutlets();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Text('Расходы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Добавляйте расходы по магазину. Руководитель видит склад, магазин и кто оформил расход.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Поиск по категории и примечанию',
                  border: OutlineInputBorder(borderRadius: AppShape.br),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded, size: 20),
                    onPressed: () {
                      search = searchCtrl.text;
                      _load();
                    },
                  ),
                ),
                onSubmitted: (_) {
                  search = searchCtrl.text;
                  _load();
                },
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickDateRange,
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: fieldBorder),
                      color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dateRange != null ? _fmtYmd(dateRange!.start) : 'Дата от',
                            style: TextStyle(fontSize: 13, color: dateRange != null ? cs.onSurface : cs.onSurfaceVariant),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        Expanded(
                          child: Text(
                            dateRange != null ? _fmtYmd(dateRange!.end) : 'Дата до',
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: 13, color: dateRange != null ? cs.onSurface : cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              if (dateRange != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() => dateRange = null);
                      _load();
                    },
                    child: const Text('Сбросить даты'),
                  ),
                ),
              ],
              if (warehouses.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: warehouseFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Склад',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('Все склады')),
                    for (final w in warehouses)
                      if (_asInt(w['id']) != null)
                        DropdownMenuItem<int>(
                          value: _asInt(w['id'])!,
                          child: Text((w['name'] ?? 'Склад ${w['id']}').toString(), overflow: TextOverflow.ellipsis),
                        ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      warehouseFilter = v;
                      mobilePage = 1;
                    });
                    _load();
                  },
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Switch(
                    value: showTrash,
                    onChanged: (v) {
                      setState(() {
                        showTrash = v;
                        mobilePage = 1;
                      });
                      _load();
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 8),
                  Text('В корзине', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => _snack('Экспорт Excel доступен в веб-версии tojir.tj'),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Excel'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Список', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        const Spacer(),
                        if (!showTrash)
                          FilledButton.icon(
                            onPressed: outlets.isEmpty ? null : _openAdd,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Добавить'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (loading && rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (loading)
                      const SkeletonListBlock(rows: 4)
                    else if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('Нет расходов.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    else ...[
                      for (final r in _mobileSlice) _expenseMobileCard(r),
                      if (rows.length > _expensesMobilePageSize) ...[
                        const SizedBox(height: 10),
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

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({
    required this.outlets,
    required this.usdToTjs,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> outlets;
  final double? usdToTjs;
  final VoidCallback onSaved;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  /// null = общий расход по складу (без магазина)
  int? outletId;
  static const int _generalExpenseSentinel = -1;
  final TextEditingController categoryCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  String currency = 'TJS';
  DateTime expenseDate = DateTime.now();
  final TextEditingController noteCtrl = TextEditingController();

  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.outlets.length == 1) outletId = _asInt(widget.outlets.first['id']);
  }

  @override
  void dispose() {
    categoryCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpenseDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDate: expenseDate,
    );
    if (d == null || !mounted) return;
    setState(() => expenseDate = d);
  }

  Future<void> _save() async {
    final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (outletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите магазин или «Общий расход»')),
      );
      return;
    }
    if (categoryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите категорию')));
      return;
    }
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите сумму')));
      return;
    }

    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final body = <String, dynamic>{
        'amount': amt,
        'currency': currency,
        'expense_date': _fmtYmd(expenseDate),
        'category': categoryCtrl.text.trim(),
        'note': noteCtrl.text.trim(),
      };
      if (outletId != _generalExpenseSentinel) {
        body['outlet'] = outletId;
      }
      final res = await api.post('inventory/expenses/', body: body);
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(_firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Расход добавлен')));
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
    final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Добавить расход', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: outletId,
              decoration: const InputDecoration(
                labelText: 'Магазин',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: _generalExpenseSentinel,
                  child: Text('Общий расход (весь склад)'),
                ),
                for (final o in widget.outlets)
                  if (_asInt(o['id']) != null)
                    DropdownMenuItem<int>(
                      value: _asInt(o['id'])!,
                      child: Text((o['name'] ?? 'Магазин ${o['id']}').toString()),
                    ),
              ],
              onChanged: (v) => setState(() => outletId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Вид расхода',
                hintText: 'Например: аренда, доставка, реклама',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Сумма', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
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
            if (amt != null && amt > 0) ...[
              const SizedBox(height: 6),
              ?_fxLine(amt, currency, widget.usdToTjs, cs),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(_fmtYmd(expenseDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickExpenseDate,
            ),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Примечание', border: OutlineInputBorder()),
              maxLines: 2,
              maxLength: 500,
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

class _EditExpenseSheet extends StatefulWidget {
  const _EditExpenseSheet({
    required this.record,
    required this.outlets,
    required this.usdToTjs,
    required this.onSaved,
  });

  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> outlets;
  final double? usdToTjs;
  final VoidCallback onSaved;

  @override
  State<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<_EditExpenseSheet> {
  static const int _generalExpenseSentinel = -1;
  late int? outletId;
  late final TextEditingController categoryCtrl;
  late final TextEditingController amountCtrl;
  late String currency;
  late DateTime expenseDate;
  late final TextEditingController noteCtrl;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    final outlet = _asInt(r['outlet']);
    outletId = outlet ?? _generalExpenseSentinel;
    categoryCtrl = TextEditingController(text: (r['category'] ?? '').toString());
    amountCtrl = TextEditingController(text: _asDouble(r['amount'])?.toString() ?? '');
    currency = (r['currency'] ?? 'TJS').toString();
    final dateStr = _formatExpenseDate(r['expense_date']);
    expenseDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
  }

  @override
  void dispose() {
    categoryCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpenseDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDate: expenseDate,
    );
    if (d == null || !mounted) return;
    setState(() => expenseDate = d);
  }

  Future<void> _save() async {
    final id = _asInt(widget.record['id']);
    if (id == null) return;

    final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (outletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите магазин или «Общий расход»')),
      );
      return;
    }
    if (categoryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите категорию')));
      return;
    }
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите сумму')));
      return;
    }

    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final body = <String, dynamic>{
        'amount': amt,
        'currency': currency,
        'expense_date': _fmtYmd(expenseDate),
        'category': categoryCtrl.text.trim(),
        'note': noteCtrl.text.trim(),
        'outlet': outletId == _generalExpenseSentinel ? null : outletId,
      };
      final res = await api.patch('inventory/expenses/$id/', body: body);
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Расход изменён')));
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
    final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Изменить расход', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: outletId,
              decoration: const InputDecoration(labelText: 'Магазин', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int>(
                  value: _generalExpenseSentinel,
                  child: Text('Общий расход (весь склад)'),
                ),
                for (final o in widget.outlets)
                  if (_asInt(o['id']) != null)
                    DropdownMenuItem<int>(
                      value: _asInt(o['id'])!,
                      child: Text((o['name'] ?? 'Магазин ${o['id']}').toString()),
                    ),
              ],
              onChanged: (v) => setState(() => outletId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtrl,
              decoration: const InputDecoration(labelText: 'Вид расхода', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Сумма', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
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
            if (amt != null && amt > 0) ...[
              const SizedBox(height: 6),
              ?_fxLine(amt, currency, widget.usdToTjs, cs),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(_fmtYmd(expenseDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickExpenseDate,
            ),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Примечание', border: OutlineInputBorder()),
              maxLines: 2,
              maxLength: 500,
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

