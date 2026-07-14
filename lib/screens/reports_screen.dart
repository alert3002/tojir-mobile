import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/number_format.dart';
import '../utils/permissions.dart';
import '../utils/report_analytics.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _heroGreen = Color(0xFF22C55E);
const _heroRed = Color(0xFFEF4444);
const _blue = Color(0xFF2563EB);
const _cardBg = Color(0xFF1A2438);
const _heroGradientStart = Color(0xFF1A2438);
const _heroGradientEnd = Color(0xFF151D2E);

String _fmtDmY(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _data;
  double? _usdToTjs;
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    _range = reportsTodayRange();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      await _load();
    });
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _hasWarehouse {
    final u = _user;
    return u != null && u['role'] == 'businessman' && businessmanHasWarehouse(u);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  Future<void> _loadRate() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final v = d['usd_to_tjs'];
        final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        setState(() => _usdToTjs = (n != null && n > 0) ? n : null);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!_hasWarehouse) {
      setState(() {
        _data = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final from = fmtYmd(_range.start);
      final to = fmtYmd(_range.end);
      final res = await context.read<ApiClient>().get(
        'inventory/reports/summary/?date_from=$from&date_to=$to',
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        final d = jsonDecode(res.body);
        final detail = d is Map ? d['detail'] : null;
        throw Exception(detail is String ? detail : 'Ошибка загрузки');
      }
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _data = d;
        _loadError = null;
      });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          _loadError = msg;
          _data = null;
        });
        _snack(msg, error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRange(DateTimeRange r) {
    setState(() => _range = r);
    _load();
  }

  ({bool today, bool week, bool month}) get _presetActive {
    final d0 = fmtYmd(_range.start);
    final d1 = fmtYmd(_range.end);
    final t = fmtYmd(DateTime.now());
    final w = reportsIsoWeekRange();
    final m = reportsFullMonthRange();
    return (
      today: d0 == t && d1 == t,
      week: d0 == fmtYmd(w.start) && d1 == fmtYmd(w.end),
      month: d0 == fmtYmd(m.start) && d1 == fmtYmd(m.end),
    );
  }

  String get _periodLabel {
    final p = _data?['period'];
    if (p is Map) {
      final f = p['date_from']?.toString();
      final t = p['date_to']?.toString();
      if (f != null && t != null) return '$f — $t';
    }
    return '${fmtYmd(_range.start)} — ${fmtYmd(_range.end)}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
      locale: const Locale('ru'),
    );
    if (picked != null) {
      _setRange(DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasWarehouse) return _buildNoWarehouse(context);

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

    return AppScaffold(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadRate();
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Text('Отчёт', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(
              '${_data?['warehouse_name'] ?? _user?['warehouse_name'] ?? 'Склад'} · $_periodLabel',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 12),
            _Toolbar(
              preset: _presetActive,
              range: _range,
              onToday: () => _setRange(reportsTodayRange()),
              onWeek: () => _setRange(reportsIsoWeekRange()),
              onMonth: () => _setRange(reportsFullMonthRange()),
              onPickRange: _pickDateRange,
              onPickStart: () => _pickSingleDate(isStart: true),
              onPickEnd: () => _pickSingleDate(isStart: false),
            ),
            if (_loading)
              const SkeletonListBlock(rows: 10)
            else if (_loadError != null)
              _ErrorBlock(message: _loadError!, onRetry: _load)
            else if (_data == null)
              const _EmptyBlock(message: 'Нет данных за период')
            else
              _ReportBody(data: _data!, range: _range, usdToTjs: _usdToTjs),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSingleDate({required bool isStart}) async {
    final initial = isStart ? _range.start : _range.end;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initial,
      locale: const Locale('ru'),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    if (isStart) {
      final end = day.isAfter(_range.end) ? day : _range.end;
      _setRange(DateTimeRange(start: day, end: end));
    } else {
      final start = day.isBefore(_range.start) ? day : _range.start;
      _setRange(DateTimeRange(start: start, end: day));
    }
  }

  Widget _buildNoWarehouse(BuildContext context) {
    return AppScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text(
                'Укажите склад в профиле, чтобы видеть аналитику.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamed('/profile'),
                child: const Text('Перейти в профиль'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.preset,
    required this.range,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
    required this.onPickRange,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final ({bool today, bool week, bool month}) preset;
  final DateTimeRange range;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;
  final VoidCallback onPickRange;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PresetChip(label: 'Сегодня', active: preset.today, onTap: onToday),
            _PresetChip(label: 'Неделя', active: preset.week, onTap: onWeek),
            _PresetChip(label: 'Месяц', active: preset.month, onTap: onMonth),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Начальная дата',
                value: _fmtDmY(range.start),
                onTap: onPickStart,
                dark: dark,
                muted: muted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateField(
                label: 'Конечная дата',
                value: _fmtDmY(range.end),
                onTap: onPickEnd,
                dark: dark,
                muted: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPickRange,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_fmtDmY(range.start)} → ${_fmtDmY(range.end)}',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  Icon(Icons.calendar_month_rounded, size: 18, color: muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.dark,
    required this.muted,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool dark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
            color: dark ? _cardBg.withValues(alpha: 0.65) : Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 10, color: muted)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.calendar_today_outlined, size: 15, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _blue : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data, required this.range, this.usdToTjs});

  final Map<String, dynamic> data;
  final DateTimeRange range;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final flow = buildFlowAnalytics(data, usdToTjs);
    final cashflow = (data['cashflow_by_currency'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final daily = (data['daily_sales_tjs'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final salesByCurr = (data['sales_by_currency'] as Map?)?.cast<String, dynamic>() ?? const {};
    final retByCurr = (data['returns_by_currency'] as Map?)?.cast<String, dynamic>() ?? const {};
    final expByCurr = (data['expenses_by_currency'] as Map?)?.cast<String, dynamic>() ?? const {};
    final debtPayByCurr = (data['debt_payments_by_currency'] as Map?)?.cast<String, dynamic>() ?? const {};

    final paymentRows = rowsWithPercent(data['sales_by_payment'] as List?, usdToTjs);
    final outletRows = rowsWithPercent(data['sales_by_outlet'] as List?, usdToTjs);
    final productRowsRaw = rowsWithPercent(data['top_products'] as List?, usdToTjs, amountKey: 'revenue', currencyKey: 'currency');
    final productRows = <Map<String, dynamic>>[];
    for (var i = 0; i < productRowsRaw.length; i++) {
      productRows.add({...productRowsRaw[i], 'rank': i + 1});
    }

    var maxDaily = 1.0;
    var dailyTotal = 0.0;
    for (final d in daily) {
      final v = parseReportBalance(d['total']) ?? 0;
      if (v > maxDaily) maxDaily = v;
      dailyTotal += v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(flow: flow, usdToTjs: usdToTjs),
        const SizedBox(height: 12),
        if (flow.inflow > 0 || flow.outflow > 0) ...[
          _StructureCard(flow: flow, usdToTjs: usdToTjs),
          const SizedBox(height: 12),
        ],
        _KpiGrid(
          salesByCurr: salesByCurr,
          retByCurr: retByCurr,
          expByCurr: expByCurr,
          debtPayByCurr: debtPayByCurr,
          salesLineCount: data['sales_line_count'],
          usdToTjs: usdToTjs,
        ),
        const SizedBox(height: 12),
        if (cashflow.isNotEmpty) ...[
          _CashflowCard(cashflow: cashflow, usdToTjs: usdToTjs),
          const SizedBox(height: 12),
        ],
        if (daily.isNotEmpty) ...[
          _DailySalesCard(daily: daily, maxDaily: maxDaily, dailyTotal: dailyTotal),
          const SizedBox(height: 10),
        ],
        _MobileBreakdownCard(
          title: 'По способу оплаты',
          rows: paymentRows.map((r) => _BreakdownRow(
            title: r['label']?.toString() ?? '—',
            amount: '${fmtReportNum(r['total'])} ${r['currency']}',
            amountTjs: (r['_tjs'] as num?)?.toDouble(),
            percent: (r['percent'] as int?) ?? 0,
          )).toList(),
          usdToTjs: usdToTjs,
        ),
        const SizedBox(height: 10),
        _MobileBreakdownCard(
          title: 'По магазинам',
          color: _heroGreen,
          rows: outletRows.map((r) => _BreakdownRow(
            title: r['outlet_name']?.toString() ?? '—',
            amount: '${fmtReportNum(r['total'])} ${r['currency']}',
            amountTjs: (r['_tjs'] as num?)?.toDouble(),
            percent: (r['percent'] as int?) ?? 0,
          )).toList(),
          usdToTjs: usdToTjs,
        ),
        const SizedBox(height: 10),
        _MobileBreakdownCard(
          title: 'Топ товаров',
          color: const Color(0xFFA855F7),
          rows: productRows.map((r) => _BreakdownRow(
            title: '#${r['rank']} ${r['name']}',
            amount: '${fmtReportNum(r['revenue'])} ${r['currency']}',
            amountTjs: (r['_tjs'] as num?)?.toDouble(),
            percent: (r['percent'] as int?) ?? 0,
          )).toList(),
          usdToTjs: usdToTjs,
        ),
        if (usdToTjs != null && usdToTjs! > 0) ...[
          const SizedBox(height: 12),
          _RateCard(usdToTjs: usdToTjs!),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.flow, this.usdToTjs});

  final ReportFlowAnalytics flow;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final neg = flow.net < 0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_heroGradientStart, _heroGradientEnd],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Итого за период (TJS)', style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 4),
          Text(
            '${fmtReportNum(flow.net)} TJS',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: neg ? _heroRed : _heroGreen, height: 1.2),
          ),
          _FxLine(amount: flow.net, currency: 'TJS', usdToTjs: usdToTjs),
          if (flow.inflow > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Маржа ${flow.marginPct}% от поступлений',
              style: TextStyle(fontSize: 12, color: neg ? _heroRed : _heroGreen, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FlowMiniCard(
                  label: 'Поступило',
                  value: '${fmtReportNum(flow.inflow)} TJS',
                  amount: flow.inflow,
                  usdToTjs: usdToTjs,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FlowMiniCard(
                  label: 'Списано',
                  value: '${fmtReportNum(flow.outflow)} TJS',
                  amount: flow.outflow,
                  usdToTjs: usdToTjs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowMiniCard extends StatelessWidget {
  const _FlowMiniCard({
    required this.label,
    required this.value,
    required this.amount,
    this.usdToTjs,
  });

  final String label;
  final String value;
  final double amount;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          _FxLine(amount: amount, currency: 'TJS', usdToTjs: usdToTjs),
        ],
      ),
    );
  }
}

class _StructureCard extends StatelessWidget {
  const _StructureCard({required this.flow, this.usdToTjs});

  final ReportFlowAnalytics flow;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    return _ReportsCard(
      title: 'Структура за период',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Поступления', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          _BreakdownInline(label: 'Продажи', value: flow.sales, percent: flow.salesPctOfInflow, color: _heroGreen, usdToTjs: usdToTjs),
          _BreakdownInline(label: 'Оплаты долгов', value: flow.debtPay, percent: flow.debtPayPctOfInflow, color: const Color(0xFF3B82F6), usdToTjs: usdToTjs),
          const SizedBox(height: 8),
          const Text('Списания', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          _BreakdownInline(label: 'Расходы', value: flow.expenses, percent: flow.expensesPctOfOutflow, color: const Color(0xFFF59E0B), usdToTjs: usdToTjs),
          _BreakdownInline(label: 'Возвраты', value: flow.returns, percent: flow.returnsPctOfOutflow, color: _heroRed, usdToTjs: usdToTjs),
        ],
      ),
    );
  }
}

class _BreakdownInline extends StatelessWidget {
  const _BreakdownInline({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    this.usdToTjs,
  });

  final String label;
  final double value;
  final int percent;
  final Color color;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${fmtReportNum(value)} TJS ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        TextSpan(text: '$percent%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                      ],
                    ),
                  ),
                  _FxLine(amount: value, currency: 'TJS', usdToTjs: usdToTjs),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PctTag extends StatelessWidget {
  const _PctTag({required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$percent%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _CurrencyTag extends StatelessWidget {
  const _CurrencyTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.salesByCurr,
    required this.retByCurr,
    required this.expByCurr,
    required this.debtPayByCurr,
    required this.salesLineCount,
    this.usdToTjs,
  });

  final Map<String, dynamic> salesByCurr;
  final Map<String, dynamic> retByCurr;
  final Map<String, dynamic> expByCurr;
  final Map<String, dynamic> debtPayByCurr;
  final dynamic salesLineCount;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];

    if (salesByCurr.isEmpty) {
      tiles.add(_KpiTile(title: 'Продажи', value: '0 —', icon: Icons.payments_outlined, route: '/sales'));
    } else {
      for (final e in salesByCurr.entries) {
        tiles.add(_KpiTile(
          title: 'Продажи, ${e.key}',
          value: fmtReportNum(e.value),
          icon: Icons.payments_outlined,
          route: '/sales',
          fx: _FxLine(amount: e.value, currency: e.key, usdToTjs: usdToTjs),
        ));
      }
    }

    tiles.add(_KpiTile(
      title: 'Строк продаж',
      value: '${salesLineCount ?? 0}',
      icon: Icons.storefront_outlined,
      route: '/sales',
    ));

    if (retByCurr.isEmpty) {
      tiles.add(_KpiTile(title: 'Возвраты', value: '0', icon: Icons.undo_rounded, route: '/returns'));
    } else {
      for (final e in retByCurr.entries) {
        tiles.add(_KpiTile(title: 'Возвраты, ${e.key}', value: fmtReportNum(e.value), icon: Icons.undo_rounded, route: '/returns'));
      }
    }

    for (final e in expByCurr.entries) {
      tiles.add(_KpiTile(title: 'Расходы, ${e.key}', value: fmtReportNum(e.value), icon: Icons.account_balance_wallet_outlined, route: '/expenses'));
    }
    for (final e in debtPayByCurr.entries) {
      tiles.add(_KpiTile(title: 'Долги, ${e.key}', value: fmtReportNum(e.value), icon: Icons.show_chart_rounded, route: '/history'));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles.map((t) => SizedBox(width: w, child: t)).toList(),
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.title, required this.value, required this.icon, required this.route, this.fx});

  final String title;
  final String value;
  final IconData icon;
  final String route;
  final Widget? fx;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(route),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
            color: dark ? _cardBg : Theme.of(context).cardColor,
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
              ?fx,
            ],
          ),
        ),
      ),
    );
  }
}

class _CashflowCard extends StatelessWidget {
  const _CashflowCard({required this.cashflow, this.usdToTjs});

  final List<Map<String, dynamic>> cashflow;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return _ReportsCard(
      title: 'Касса по валютам',
      icon: Icons.calculate_outlined,
      child: Column(
        children: [
          ...cashflow.map((r) {
            final bal = parseReportBalance(r['balance']) ?? 0;
            final neg = bal < 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CurrencyTag(label: r['currency']?.toString() ?? '—'),
                      Text(fmtReportNum(r['balance']), style: TextStyle(fontWeight: FontWeight.w700, color: neg ? _heroRed : _heroGreen)),
                    ],
                  ),
                  _FxLine(amount: r['balance'], currency: r['currency']?.toString(), usdToTjs: usdToTjs),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text('+ продажи ${fmtReportNum(r['sales'])}', style: TextStyle(fontSize: 11, color: muted)),
                      Text('+ долги ${fmtReportNum(r['debt_payments'])}', style: TextStyle(fontSize: 11, color: muted)),
                      Text('− расходы ${fmtReportNum(r['expenses'])}', style: TextStyle(fontSize: 11, color: muted)),
                      Text('− возвраты ${fmtReportNum(r['returns'] ?? 0)}', style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (cashflow.isNotEmpty) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cashflow.map((r) {
                    final n = parseReportBalance(r['balance']) ?? 0;
                    return SizedBox(
                      width: w,
                      child: Material(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pushNamed('/history'),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['currency']?.toString() ?? '—', style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  '${fmtReportNum(r['balance'])} ${r['currency']}',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: n < 0 ? _heroRed : _heroGreen),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DailySalesCard extends StatelessWidget {
  const _DailySalesCard({required this.daily, required this.maxDaily, required this.dailyTotal});

  final List<Map<String, dynamic>> daily;
  final double maxDaily;
  final double dailyTotal;

  @override
  Widget build(BuildContext context) {
    return _ReportsCard(
      title: 'Продажи по дням (TJS)',
      child: Column(
        children: daily.map((d) {
          final daySum = parseReportBalance(d['total']) ?? 0;
          final dayPct = percentOf(daySum, dailyTotal);
          final barPct = (daySum / maxDaily * 100).round().clamp(0, 100);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(d['date']?.toString() ?? '—', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)))),
                    _PctTag(percent: dayPct, color: _blue),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${fmtReportNum(d['total'])} TJS', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: barPct / 100,
                    minHeight: 6,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: _blue,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BreakdownRow {
  const _BreakdownRow({required this.title, required this.amount, required this.percent, this.amountTjs});
  final String title;
  final String amount;
  final int percent;
  final double? amountTjs;
}

class _MobileBreakdownCard extends StatelessWidget {
  const _MobileBreakdownCard({
    required this.title,
    required this.rows,
    this.color = _blue,
    this.usdToTjs,
  });

  final String title;
  final List<_BreakdownRow> rows;
  final Color color;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final body = rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Нет данных', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
          )
        : Column(
            children: rows.map((r) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(r.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      Text('${r.percent}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                    ],
                  ),
                  Text(r.amount, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75))),
                  if (r.amountTjs != null) _FxLine(amount: r.amountTjs, currency: 'TJS', usdToTjs: usdToTjs),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: r.percent / 100,
                      minHeight: 6,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: color,
                    ),
                  ),
                ],
              ),
            )).toList(),
          );

    return _ReportsCard(title: title, child: body);
  }
}

class _ReportsCard extends StatelessWidget {
  const _ReportsCard({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: dark ? _cardBg : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.usdToTjs});
  final double usdToTjs;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? _cardBg : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                children: [
                  const TextSpan(text: 'Курс для расчётов: '),
                  TextSpan(text: '1 USD = ${fmtReportNum(usdToTjs)} TJS', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/exchange-rate'),
            style: TextButton.styleFrom(
              foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Изменить курс', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _FxLine extends StatelessWidget {
  const _FxLine({required this.amount, this.currency, this.usdToTjs});

  final dynamic amount;
  final String? currency;
  final double? usdToTjs;

  @override
  Widget build(BuildContext context) {
    final cur = (currency ?? 'TJS').trim().toUpperCase();
    final n = amount is num ? amount.toDouble() : parseReportBalance(amount);
    if (n == null || n == 0 || usdToTjs == null || usdToTjs! <= 0) return const SizedBox.shrink();
    String? text;
    if (cur == 'TJS') {
      text = '≈ ${formatRuMoney(n / usdToTjs!, fractionDigits: 2)} USD';
    } else if (cur == 'USD') {
      text = '≈ ${formatRuMoney(n * usdToTjs!, fractionDigits: 2)} TJS';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55), height: 1.35)),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)))),
    );
  }
}
