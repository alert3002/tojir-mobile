import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/date_range_presets.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/quick_date_range_chips.dart';

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
  String? datePresetKey;

  bool showTrash = false;

  List<Map<String, dynamic>> warehouses = const [];
  int? warehouseFilter;

  List<Map<String, dynamic>> outlets = const [];
  double? usdToTjs;

  int? deletingId;

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
      setState(() => rows = list);
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
    );
    if (picked == null || !mounted) return;
    setState(() {
      dateRange = picked;
      datePresetKey = 'period';
    });
    await _load();
  }

  void _clearDateRange() {
    setState(() {
      dateRange = null;
      datePresetKey = null;
    });
    _load();
  }

  void _applyDateQuick(String kind) {
    if (kind == 'period') {
      _pickDateRange();
      return;
    }
    final r = DateRangePresets.rangeForPreset(kind);
    if (r == null) return;
    setState(() {
      datePresetKey = kind;
      dateRange = r;
    });
    _load();
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

  Widget _rowTile(Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    final id = _asInt(r['id']);
    final date = (r['expense_date'] ?? '—').toString();
    final wh = (r['warehouse_name'] ?? '—').toString();
    final outlet = (r['outlet_name'] ?? '—').toString();
    final who = (r['created_by_display'] ?? '—').toString();
    final cat = (r['category'] ?? '—').toString();
    final cur = (r['currency'] ?? 'TJS').toString();
    final amt = _asDouble(r['amount']);
    final note = (r['note'] ?? '').toString();

    const compactConstraints = BoxConstraints.tightFor(width: 36, height: 36);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                      Text(date.length >= 10 ? date.substring(0, 10) : date, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Склад: $wh', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      Text('Магазин: $outlet', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      Text('Кто: $who', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      Text('Вид: $cat', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 0,
                  children: [
                    if (showTrash)
                      IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: 'Восстановить',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: compactConstraints,
                        onPressed: () => _restore(r),
                      ),
                    IconButton(
                      icon: deletingId == id
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(showTrash ? Icons.delete_forever : Icons.delete_outline),
                      tooltip: showTrash ? 'Удалить навсегда' : 'Удалить',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: compactConstraints,
                      onPressed: deletingId == id ? null : () => _delete(r, permanent: showTrash),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (amt != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сумма', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  Text('${_formatMoneyRu(amt)} $cur', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ?_fxLine(amt, cur, usdToTjs, cs),
                ],
              )
            else
              Text('Сумма: —', style: TextStyle(color: cs.onSurfaceVariant)),
            if (note.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Примечание: $note', style: TextStyle(fontSize: 12, color: cs.onSurface)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('Расходы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Добавляйте расходы по магазину. Руководитель видит склад, магазин и кто оформил расход.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Поиск по категории и примечанию',
                  border: OutlineInputBorder(borderRadius: AppShape.br),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
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
              const SizedBox(height: 10),
              QuickDateRangeChips(
                colorScheme: cs,
                selected: datePresetKey,
                onToday: () => _applyDateQuick('today'),
                onWeek: () => _applyDateQuick('week'),
                onMonth: () => _applyDateQuick('month'),
                onPeriod: () => _applyDateQuick('period'),
              ),
              if (dateRange != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_fmtYmd(dateRange!.start)} — ${_fmtYmd(dateRange!.end)}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      onPressed: _clearDateRange,
                      icon: const Icon(Icons.clear),
                      tooltip: 'Сбросить период',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (warehouses.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  value: warehouseFilter,
                  decoration: const InputDecoration(labelText: 'Склад', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('Все склады')),
                    for (final w in warehouses)
                      if (_asInt(w['id']) != null)
                        DropdownMenuItem<int>(
                          value: _asInt(w['id'])!,
                          child: Text((w['name'] ?? 'Склад ${w['id']}').toString()),
                        ),
                  ],
                  onChanged: (v) {
                    setState(() => warehouseFilter = v);
                    _load();
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Switch(
                    value: showTrash,
                    onChanged: (v) {
                      setState(() => showTrash = v);
                      _load();
                    },
                  ),
                  Text('В корзине', style: TextStyle(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  if (!showTrash)
                    FilledButton.icon(
                      onPressed: outlets.isEmpty ? null : _openAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить расход'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading)
                const SkeletonListBlock(rows: 6)
else if (rows.isEmpty)
                Text('Нет расходов.', style: TextStyle(color: cs.onSurfaceVariant))
              else
                ...rows.map(_rowTile),
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
  int? outletId;
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите магазин')));
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
      final res = await api.post(
        'inventory/expenses/',
        body: {
          'amount': amt,
          'currency': currency,
          'expense_date': _fmtYmd(expenseDate),
          'category': categoryCtrl.text.trim(),
          'outlet': outletId,
          'note': noteCtrl.text.trim(),
        },
      );
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
              decoration: const InputDecoration(labelText: 'Магазин', border: OutlineInputBorder()),
              items: [
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

