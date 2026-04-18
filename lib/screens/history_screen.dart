import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/date_range_presets.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/quick_date_range_chips.dart';

const _kindFilterOptions = <MapEntry<String, String>>[
  MapEntry('sale', 'Продажа'),
  MapEntry('return', 'Возврат'),
  MapEntry('transfer', 'Перемещение'),
  MapEntry('expense', 'Расход'),
  MapEntry('debt_payment', 'Оплата долга'),
  MapEntry('debt_new', 'Долг клиента'),
];

const _kindColors = <String, Color>{
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
  var intPart = s.substring(0, dot);
  final dec = s.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('\u00A0');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}${buf.toString()}$dec';
}

String _formatAt(dynamic v) {
  if (v == null) return '—';
  final s = v.toString().replaceFirst('T', ' ');
  if (s.length > 19) return s.substring(0, 19);
  if (s.length > 16) return s.substring(0, 16);
  return s;
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
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

  int page = 1;
  int pageSize = 40;

  DateTimeRange? dateRange;
  String? datePresetKey;
  String? kindFilter;
  int? outletFilter;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';

  List<Map<String, dynamic>> outletOptions = const [];
  double? usdToTjs;

  Timer? _searchDebounce;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _isSeller => (_user?['role'] as String?) == 'seller';

  bool get _showOutletFilter {
    final u = _user;
    if (u == null) return false;
    return (u['role'] as String?) == 'businessman' && u['warehouse'] != null;
  }

  @override
  void initState() {
    super.initState();
    searchCtrl.addListener(_onSearchText);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      if (_showOutletFilter) await _loadOutletOptions();
      await _loadFeed();
    });
  }

  void _onSearchText() {
    final v = searchCtrl.text;
    if (v == search) return;
    search = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => page = 1);
        _loadFeed();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchCtrl.dispose();
    super.dispose();
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
        'page_size': pageSize.toString(),
      };
      if (dateRange != null) {
        final a = dateRange!.start;
        final b = dateRange!.end;
        qp['date_from'] =
            '${a.year.toString().padLeft(4, '0')}-${a.month.toString().padLeft(2, '0')}-${a.day.toString().padLeft(2, '0')}';
        qp['date_to'] =
            '${b.year.toString().padLeft(4, '0')}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';
      }
      if (search.trim().isNotEmpty) qp['search'] = search.trim();
      if (kindFilter != null && kindFilter!.isNotEmpty) qp['kind'] = kindFilter!;
      if (outletFilter != null) qp['outlet_id'] = outletFilter.toString();

      final path = 'inventory/history/feed/?${Uri(queryParameters: qp).query}';
      final res = await context.read<ApiClient>().get(path);
      if (!mounted) return;
      if (res.statusCode != 200) {
        final body = res.body.isEmpty ? <String, dynamic>{} : _tryJsonMap(res.body);
        final msg = body['detail']?.toString() ?? 'Ошибка';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
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

  Widget? _fxSubtitle(dynamic amount, String? currency, ColorScheme cs) {
    final cur = (currency ?? '').trim().toUpperCase();
    final n = amount is num && amount.isFinite ? amount.toDouble() : _parseMoneyNumber(amount);
    final rate = usdToTjs;
    if (n == null || n == 0 || rate == null || rate <= 0) return null;
    if (cur == 'TJS') {
      final usd = n / rate;
      return Text(
        '≈ ${_formatMoneyRu(usd)} USD',
        style: TextStyle(fontSize: 11, height: 1.35, color: cs.onSurfaceVariant),
      );
    }
    if (cur == 'USD') {
      final tjs = n * rate;
      return Text(
        '≈ ${_formatMoneyRu(tjs)} TJS',
        style: TextStyle(fontSize: 11, height: 1.35, color: cs.onSurfaceVariant),
      );
    }
    return null;
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
      page = 1;
    });
    await _loadFeed();
  }

  void _clearDateRange() {
    setState(() {
      dateRange = null;
      datePresetKey = null;
      page = 1;
    });
    _loadFeed();
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
      page = 1;
    });
    _loadFeed();
  }

  int get _totalPages {
    if (total <= 0) return 1;
    return (total + pageSize - 1) ~/ pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'history', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'История',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                _isSeller
                    ? 'Ваши операции: продажи, возвраты, перемещения, расходы, долги и оплаты, которые вы оформили.'
                    : 'Все операции по вашему складу: видно, кто и в каком магазине действовал.',
                style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              _FilterCard(
                dark: dark,
                cs: cs,
                searchCtrl: searchCtrl,
                kindFilter: kindFilter,
                onKindChanged: (v) {
                  setState(() {
                    kindFilter = v;
                    page = 1;
                  });
                  _loadFeed();
                },
                showOutletFilter: _showOutletFilter,
                outletOptions: outletOptions,
                outletFilter: outletFilter,
                onOutletChanged: (v) {
                  setState(() {
                    outletFilter = v;
                    page = 1;
                  });
                  _loadFeed();
                },
                dateRange: dateRange,
                datePresetKey: datePresetKey,
                onToday: () => _applyDateQuick('today'),
                onWeek: () => _applyDateQuick('week'),
                onMonth: () => _applyDateQuick('month'),
                onPeriod: () => _applyDateQuick('period'),
                onClearRange: dateRange != null ? _clearDateRange : null,
              ),
              const SizedBox(height: 14),
              if (loading && rows.isEmpty) const SkeletonListBlock(rows: 7)
else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'Нет записей за выбранный период.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else ...[
                for (final r in rows)
                  _HistoryRowCard(
                    record: r,
                    cs: cs,
                    dark: dark,
                    showWarehouse: !_isSeller,
                    showActor: !_isSeller,
                    formatAt: _formatAt,
                    formatMoney: _formatMoneyRu,
                    parseMoney: _parseMoneyNumber,
                    fxSubtitle: _fxSubtitle,
                    kindColors: _kindColors,
                  ),
              ],
              const SizedBox(height: 16),
              _PaginationBar(
                cs: cs,
                page: page,
                totalPages: _totalPages,
                pageSize: pageSize,
                total: total,
                loading: loading,
                onPrev: page > 1
                    ? () {
                        setState(() => page -= 1);
                        _loadFeed();
                      }
                    : null,
                onNext: page < _totalPages
                    ? () {
                        setState(() => page += 1);
                        _loadFeed();
                      }
                    : null,
                onPageSize: (ps) {
                  setState(() {
                    pageSize = ps;
                    page = 1;
                  });
                  _loadFeed();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.dark,
    required this.cs,
    required this.searchCtrl,
    required this.kindFilter,
    required this.onKindChanged,
    required this.showOutletFilter,
    required this.outletOptions,
    required this.outletFilter,
    required this.onOutletChanged,
    required this.dateRange,
    required this.datePresetKey,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
    required this.onPeriod,
    this.onClearRange,
  });

  final bool dark;
  final ColorScheme cs;
  final TextEditingController searchCtrl;
  final String? kindFilter;
  final void Function(String?) onKindChanged;
  final bool showOutletFilter;
  final List<Map<String, dynamic>> outletOptions;
  final int? outletFilter;
  final void Function(int?) onOutletChanged;
  final DateTimeRange? dateRange;
  final String? datePresetKey;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;
  final VoidCallback onPeriod;
  final VoidCallback? onClearRange;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              hintText: 'Поиск по описанию, типу, сотруднику, магазину',
              hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(isDense: true, labelText: 'Тип операции', border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: kindFilter,
                hint: const Text('Все типы'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Все типы')),
                  ..._kindFilterOptions.map(
                    (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: onKindChanged,
              ),
            ),
          ),
          if (showOutletFilter) ...[
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(isDense: true, labelText: 'Магазин', border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  isExpanded: true,
                  value: outletFilter,
                  hint: const Text('Все магазины'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Все магазины')),
                    ...outletOptions.map((o) {
                      final id = _asInt(o['id']);
                      if (id == null) return null;
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text((o['name'] ?? 'Магазин #$id').toString()),
                      );
                    }).whereType<DropdownMenuItem<int?>>(),
                  ],
                  onChanged: onOutletChanged,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text('Период', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          QuickDateRangeChips(
            colorScheme: cs,
            selected: datePresetKey,
            onToday: onToday,
            onWeek: onWeek,
            onMonth: onMonth,
            onPeriod: onPeriod,
          ),
          if (dateRange != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '${dateRange!.start.year}-${dateRange!.start.month.toString().padLeft(2, '0')}-${dateRange!.start.day.toString().padLeft(2, '0')} — ${dateRange!.end.year}-${dateRange!.end.month.toString().padLeft(2, '0')}-${dateRange!.end.day.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                if (onClearRange != null)
                  TextButton(
                    onPressed: onClearRange,
                    child: const Text('Сбросить'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRowCard extends StatelessWidget {
  const _HistoryRowCard({
    required this.record,
    required this.cs,
    required this.dark,
    required this.showWarehouse,
    required this.showActor,
    required this.formatAt,
    required this.formatMoney,
    required this.parseMoney,
    required this.fxSubtitle,
    required this.kindColors,
  });

  final Map<String, dynamic> record;
  final ColorScheme cs;
  final bool dark;
  final bool showWarehouse;
  final bool showActor;
  final String Function(dynamic) formatAt;
  final String Function(double) formatMoney;
  final double? Function(dynamic) parseMoney;
  final Widget? Function(dynamic amount, String? currency, ColorScheme cs) fxSubtitle;
  final Map<String, Color> kindColors;

  @override
  Widget build(BuildContext context) {
    final kind = (record['kind'] ?? '').toString();
    final label = (record['kind_label'] ?? kind).toString();
    final tagColor = kindColors[kind] ?? cs.primary;
    final amount = record['amount'];
    final currency = record['currency']?.toString();
    String amountLine = '—';
    if (amount != null) {
      final n = parseMoney(amount);
      amountLine = n != null ? '${formatMoney(n)} ${currency ?? ''}'.trim() : amount.toString();
    }
    final fx = fxSubtitle(amount, currency, cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        borderRadius: AppShape.br,
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
                          formatAt(record['at']),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: dark ? 0.28 : 0.18),
                            borderRadius: AppShape.br,
                          ),
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(amountLine, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.onSurface)),
                      ?fx,
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (record['summary'] ?? '—').toString(),
                style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurface),
              ),
              if (showWarehouse) ...[
                const SizedBox(height: 6),
                Text(
                  'Склад: ${(record['warehouse_name'] ?? '—').toString()}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Магазин: ${(record['outlet_name'] ?? '—').toString()}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              if (showActor) ...[
                const SizedBox(height: 4),
                Text(
                  'Кто: ${(record['actor_name'] ?? '—').toString()}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.cs,
    required this.page,
    required this.totalPages,
    required this.pageSize,
    required this.total,
    required this.loading,
    this.onPrev,
    this.onNext,
    required this.onPageSize,
  });

  final ColorScheme cs;
  final int page;
  final int totalPages;
  final int pageSize;
  final int total;
  final bool loading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(int) onPageSize;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = (page * pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        children: [
          Text(
            total == 0 ? '0 записей' : '$from–$to из $total',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: loading ? null : onPrev,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Стр. $page / $totalPages', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
              ),
              IconButton.filledTonal(
                onPressed: loading ? null : onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [20, 40, 80, 100].map((ps) {
              final sel = ps == pageSize;
              return ChoiceChip(
                label: Text('$ps'),
                selected: sel,
                onSelected: loading
                    ? null
                    : (_) {
                        if (!sel) onPageSize(ps);
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
