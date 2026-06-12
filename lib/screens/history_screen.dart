import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _mobilePageSize = 20;
const _cardBg = Color(0xFF1A2438);
const _blue = Color(0xFF2563EB);

const _kindFilterOptions = <MapEntry<String, String>>[
  MapEntry('sale', 'Продажа'),
  MapEntry('return', 'Возврат'),
  MapEntry('transfer', 'Перемещение'),
  MapEntry('expense', 'Расход'),
  MapEntry('debt_payment', 'Оплата долга'),
  MapEntry('debt_new', 'Долг клиента'),
];

const _kindTagColors = <String, Color>{
  'sale': Color(0xFF22C55E),
  'return': Color(0xFFF97316),
  'transfer': Color(0xFF06B6D4),
  'expense': Color(0xFFEF4444),
  'debt_payment': Color(0xFF3B82F6),
  'debt_new': Color(0xFFA855F7),
};

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

String _formatAtShort(dynamic v) {
  if (v == null) return '—';
  final s = v.toString().replaceFirst('T', ' ');
  final date = s.length >= 10 ? s.substring(0, 10) : s;
  final time = s.length >= 16 ? s.substring(11, 16) : '';
  return time.isNotEmpty ? '$date · $time' : date;
}

String _fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

String _formatIntRu(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u00A0');
    buf.write(s[i]);
  }
  return buf.toString();
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> rows = const [];
  int total = 0;
  bool loading = false;
  bool exporting = false;
  bool filtersOpen = false;

  int page = 1;

  DateTimeRange? dateRange;
  String? kindFilter;
  int? outletFilter;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';

  List<Map<String, dynamic>> outletOptions = const [];
  double? usdToTjs;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _showOutletFilter {
    final u = _user;
    if (u == null) return false;
    return (u['role'] as String?) == 'businessman' && u['warehouse'] != null;
  }

  int get _activeFilterCount {
    var n = 0;
    if (search.trim().isNotEmpty) n++;
    if (kindFilter != null && kindFilter!.isNotEmpty) n++;
    if (outletFilter != null) n++;
    if (dateRange != null) n++;
    return n;
  }

  int get _totalPages {
    if (total <= 0) return 1;
    return (total + _mobilePageSize - 1) ~/ _mobilePageSize;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      if (_showOutletFilter) await _loadOutletOptions();
      await _loadFeed();
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

  void _applySearch([String? v]) {
    setState(() {
      search = (v ?? searchCtrl.text).trim();
      page = 1;
    });
    _loadFeed();
  }

  void _clearFilters() {
    setState(() {
      search = '';
      searchCtrl.clear();
      kindFilter = null;
      outletFilter = null;
      dateRange = null;
      page = 1;
    });
    _loadFeed();
  }

  Future<void> _loadRate() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/rate/');
      if (!mounted || res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final v = d['usd_to_tjs'];
      final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
      setState(() => usdToTjs = (n != null && n.isFinite && n > 0) ? n : null);
    } catch (_) {
      if (mounted) setState(() => usdToTjs = null);
    }
  }

  Future<void> _loadOutletOptions() async {
    final u = _user;
    final wh = u?['warehouse'];
    if (wh == null) {
      setState(() => outletOptions = const []);
      return;
    }
    final wid = wh is int ? wh : (wh is num ? wh.toInt() : int.tryParse(wh.toString()));
    if (wid == null) {
      setState(() => outletOptions = const []);
      return;
    }
    try {
      final res = await context.read<ApiClient>().get('inventory/outlets?warehouse=$wid');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? d['data']) : null);
        final items = (list is List) ? list.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => outletOptions = items);
      }
    } catch (_) {
      if (mounted) setState(() => outletOptions = const []);
    }
  }

  Future<void> _loadFeed() async {
    setState(() => loading = true);
    try {
      final qp = <String, String>{
        'page': page.toString(),
        'page_size': _mobilePageSize.toString(),
      };
      if (dateRange != null) {
        qp['date_from'] = _fmtYmd(dateRange!.start);
        qp['date_to'] = _fmtYmd(dateRange!.end);
      }
      if (search.trim().isNotEmpty) qp['search'] = search.trim();
      if (kindFilter != null && kindFilter!.isNotEmpty) qp['kind'] = kindFilter!;
      if (outletFilter != null) qp['outlet_id'] = outletFilter.toString();

      final path = 'inventory/history/feed/?${Uri(queryParameters: qp).query}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode != 200) {
        final body = res.body.isEmpty ? <String, dynamic>{} : _tryJsonMap(res.body);
        _snack(body['detail']?.toString() ?? 'Ошибка', error: true);
        setState(() {
          rows = const [];
          total = 0;
        });
        return;
      }
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (d['results'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        rows = list;
        total = _asInt(d['count']) ?? 0;
      });
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
        setState(() {
          rows = const [];
          total = 0;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
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

  Future<void> _exportExcel() async {
    setState(() => exporting = true);
    try {
      final qp = <String, String>{'page': '1', 'page_size': '5000'};
      if (dateRange != null) {
        qp['date_from'] = _fmtYmd(dateRange!.start);
        qp['date_to'] = _fmtYmd(dateRange!.end);
      }
      if (search.trim().isNotEmpty) qp['search'] = search.trim();
      if (kindFilter != null && kindFilter!.isNotEmpty) qp['kind'] = kindFilter!;
      if (outletFilter != null) qp['outlet_id'] = outletFilter.toString();

      final res = await context.read<ApiClient>().get('inventory/history/feed/?${Uri(queryParameters: qp).query}');
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('Ошибка экспорта');
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (d['results'] as List?) ?? [];
      if (list.isEmpty) {
        _snack('Нет данных', error: true);
        return;
      }
      _snack('Экспорт Excel доступен в веб-версии tojir.tj');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => exporting = false);
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
    setState(() {
      dateRange = picked;
      page = 1;
    });
    await _loadFeed();
  }

  Widget? _fxLine(dynamic amount, String? currency) {
    final cur = (currency ?? '').trim().toUpperCase();
    final n = amount is num && amount.isFinite ? amount.toDouble() : _parseMoneyNumber(amount);
    final rate = usdToTjs;
    if (n == null || n == 0 || rate == null || rate <= 0) return null;
    if (cur == 'TJS') {
      return Text('≈ ${_formatMoneyRu(n / rate)} USD', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45)));
    }
    if (cur == 'USD') {
      return Text('≈ ${_formatMoneyRu(n * rate)} TJS', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45)));
    }
    return null;
  }

  ({Color bg, Color border, Color text}) _amountStyle(String kind) {
    switch (kind) {
      case 'expense':
      case 'return':
        return (bg: const Color(0xFFEF4444).withValues(alpha: 0.1), border: const Color(0xFFEF4444).withValues(alpha: 0.22), text: const Color(0xFFFCA5A5));
      case 'transfer':
        return (bg: const Color(0xFF06B6D4).withValues(alpha: 0.1), border: const Color(0xFF06B6D4).withValues(alpha: 0.22), text: const Color(0xFF67E8F9));
      case 'debt_payment':
        return (bg: _blue.withValues(alpha: 0.1), border: _blue.withValues(alpha: 0.22), text: const Color(0xFF93C5FD));
      case 'debt_new':
        return (bg: const Color(0xFFA855F7).withValues(alpha: 0.1), border: const Color(0xFFA855F7).withValues(alpha: 0.22), text: const Color(0xFFD8B4FE));
      default:
        return (bg: const Color(0xFF22C55E).withValues(alpha: 0.1), border: const Color(0xFF22C55E).withValues(alpha: 0.22), text: const Color(0xFF86EFAC));
    }
  }

  Widget _kindTag(String kind, String label) {
    final color = _kindTagColors[kind] ?? _blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.95), height: 1.4)),
    );
  }

  Widget _mobileCard(Map<String, dynamic> r) {
    final kind = (r['kind'] ?? '').toString();
    final label = (r['kind_label'] ?? kind).toString();
    final summary = (r['summary'] ?? '—').toString();
    final amount = r['amount'];
    final currency = r['currency']?.toString();
    final outletName = (r['outlet_name'] ?? '').toString().trim();
    final amountStyle = _amountStyle(kind);

    String amountText = '';
    if (amount != null) {
      final n = _parseMoneyNumber(amount);
      amountText = n != null ? '${_formatMoneyRu(n)} ${currency ?? ''}'.trim() : amount.toString();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _kindTag(kind, label),
              const Spacer(),
              Text(_formatAtShort(r['at']), style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.35, color: Colors.white.withValues(alpha: 0.92))),
          if (amount != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: amountStyle.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: amountStyle.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(amountText, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: amountStyle.text, height: 1.25)),
                  if (_fxLine(amount, currency) != null) _fxLine(amount, currency)!,
                ],
              ),
            ),
          ],
          if (outletName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Магазин', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
                  const SizedBox(height: 2),
                  Text(outletName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.88))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filtersPanel(ColorScheme cs, bool dark) {
    final fieldBorder = dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            value: kindFilter,
            decoration: const InputDecoration(labelText: 'Тип операции', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Все типы')),
              ..._kindFilterOptions.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) {
              setState(() {
                kindFilter = v;
                page = 1;
              });
              _loadFeed();
            },
          ),
          if (_showOutletFilter) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: outletFilter,
              decoration: const InputDecoration(labelText: 'Магазин', border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Все магазины')),
                ...outletOptions.map((o) {
                  final id = _asInt(o['id']);
                  if (id == null) return null;
                  return DropdownMenuItem<int?>(value: id, child: Text((o['name'] ?? 'Магазин #$id').toString()));
                }).whereType<DropdownMenuItem<int?>>(),
              ],
              onChanged: (v) {
                setState(() {
                  outletFilter = v;
                  page = 1;
                });
                _loadFeed();
              },
            ),
          ],
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
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _clearFilters, child: const Text('Сбросить фильтры')),
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

    if (u == null || !canAccessSection(u, 'history', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            if (_showOutletFilter) await _loadOutletOptions();
            await _loadFeed();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Row(
                children: [
                  Expanded(child: Text('История', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface))),
                  OutlinedButton.icon(
                    onPressed: exporting ? null : _exportExcel,
                    icon: exporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Excel'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Поиск...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded, size: 20),
                          onPressed: () => _applySearch(),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _applySearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => filtersOpen = !filtersOpen),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.filter_list_rounded, size: 18),
                        if (_activeFilterCount > 0)
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                              child: Text(
                                '$_activeFilterCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                    label: const Text('Фильтры'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: fieldBorder)),
                    ),
                  ),
                ],
              ),
              if (filtersOpen) _filtersPanel(cs, dark),
              if (total > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${_formatIntRu(total)} записей',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              if (loading && rows.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (loading)
                const SkeletonListBlock(rows: 5)
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Нет записей за выбранный период', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                )
              else
                for (final r in rows) _mobileCard(r),
              if (total > _mobilePageSize) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: page > 1 && !loading
                          ? () {
                              setState(() => page--);
                              _loadFeed();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text('$page / $_totalPages', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    IconButton(
                      onPressed: page < _totalPages && !loading
                          ? () {
                              setState(() => page++);
                              _loadFeed();
                            }
                          : null,
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
