import 'package:flutter/material.dart';

import 'number_format.dart';

double? parseReportBalance(dynamic v) {
  if (v == null || v == '') return null;
  if (v is num && v.isFinite) return v.toDouble();
  final t = v.toString().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Сумма в TJS (USD × курс; остальные валюты — как есть).
double toTjsEquiv(dynamic amount, String? currency, double? usdToTjs) {
  final n = parseReportBalance(amount) ?? 0;
  final c = (currency ?? 'TJS').trim().toUpperCase();
  if (c == 'TJS') return n;
  if (c == 'USD' && usdToTjs != null && usdToTjs > 0) return n * usdToTjs;
  return n;
}

double sumCurrencyMap(Map<String, dynamic>? map, double? usdToTjs) {
  var sum = 0.0;
  for (final e in (map ?? const {}).entries) {
    sum += toTjsEquiv(e.value, e.key, usdToTjs);
  }
  return sum;
}

int percentOf(num part, num total) {
  final t = total.toDouble();
  if (t <= 0) return 0;
  final p = part.toDouble();
  return (p / t * 100).round().clamp(0, 100);
}

List<Map<String, dynamic>> rowsWithPercent(
  List<dynamic>? rows,
  double? usdToTjs, {
  String amountKey = 'total',
  String currencyKey = 'currency',
}) {
  final list = (rows ?? const <dynamic>[]).cast<Map<String, dynamic>>();
  final enriched = list.map((r) {
    final tjs = toTjsEquiv(r[amountKey], r[currencyKey]?.toString(), usdToTjs);
    return {...r, '_tjs': tjs};
  }).toList();
  final totalTjs = enriched.fold<double>(0, (s, r) => s + ((r['_tjs'] as num?)?.toDouble() ?? 0));
  enriched.sort((a, b) => ((b['_tjs'] as num?) ?? 0).compareTo((a['_tjs'] as num?) ?? 0));
  return enriched.map((r) => {...r, 'percent': percentOf(r['_tjs'] ?? 0, totalTjs)}).toList();
}

class ReportFlowAnalytics {
  const ReportFlowAnalytics({
    required this.sales,
    required this.expenses,
    required this.returns,
    required this.debtPay,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.salesPctOfInflow,
    required this.debtPayPctOfInflow,
    required this.expensesPctOfOutflow,
    required this.returnsPctOfOutflow,
    required this.marginPct,
  });

  final double sales;
  final double expenses;
  final double returns;
  final double debtPay;
  final double inflow;
  final double outflow;
  final double net;
  final int salesPctOfInflow;
  final int debtPayPctOfInflow;
  final int expensesPctOfOutflow;
  final int returnsPctOfOutflow;
  final int marginPct;
}

ReportFlowAnalytics buildFlowAnalytics(Map<String, dynamic>? data, double? usdToTjs) {
  final salesMap = data?['sales_by_currency'];
  final expMap = data?['expenses_by_currency'];
  final retMap = data?['returns_by_currency'];
  final debtMap = data?['debt_payments_by_currency'];

  final sales = sumCurrencyMap(salesMap is Map ? salesMap.cast<String, dynamic>() : null, usdToTjs);
  final expenses = sumCurrencyMap(expMap is Map ? expMap.cast<String, dynamic>() : null, usdToTjs);
  final returns = sumCurrencyMap(retMap is Map ? retMap.cast<String, dynamic>() : null, usdToTjs);
  final debtPay = sumCurrencyMap(debtMap is Map ? debtMap.cast<String, dynamic>() : null, usdToTjs);
  final inflow = sales + debtPay;
  final outflow = expenses + returns;
  final net = inflow - outflow;

  return ReportFlowAnalytics(
    sales: sales,
    expenses: expenses,
    returns: returns,
    debtPay: debtPay,
    inflow: inflow,
    outflow: outflow,
    net: net,
    salesPctOfInflow: percentOf(sales, inflow),
    debtPayPctOfInflow: percentOf(debtPay, inflow),
    expensesPctOfOutflow: percentOf(expenses, outflow),
    returnsPctOfOutflow: percentOf(returns, outflow),
    marginPct: inflow > 0 ? percentOf(net, inflow) : 0,
  );
}

String fmtReportNum(dynamic s) {
  final n = parseReportBalance(s);
  if (n == null) return '—';
  return formatRuMoney(n, fractionDigits: 2);
}

class ConsolidatedItog {
  const ConsolidatedItog({
    required this.sum,
    required this.hasUsd,
    required this.usdMissingRate,
    required this.others,
  });

  final double sum;
  final bool hasUsd;
  final bool usdMissingRate;
  final List<String> others;
}

ConsolidatedItog? buildConsolidatedItog(List<dynamic>? cashflow, double? usdToTjs) {
  final list = (cashflow ?? const <dynamic>[]).cast<Map<String, dynamic>>();
  if (list.isEmpty) return null;
  var sum = 0.0;
  var hasUsd = false;
  var usdMissingRate = false;
  final others = <String>{};
  for (final r in list) {
    final n = parseReportBalance(r['balance']) ?? 0;
    final c = (r['currency'] ?? '').toString().trim().toUpperCase();
    if (c == 'TJS') {
      sum += n;
    } else if (c == 'USD') {
      hasUsd = true;
      if (usdToTjs != null && usdToTjs > 0) {
        sum += n * usdToTjs;
      } else {
        usdMissingRate = true;
      }
    } else if (c.isNotEmpty) {
      others.add(c);
    }
  }
  return ConsolidatedItog(sum: sum, hasUsd: hasUsd, usdMissingRate: usdMissingRate, others: others.toList());
}

String fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTimeRange reportsTodayRange() {
  final t = DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  return DateTimeRange(start: d, end: d);
}

DateTimeRange reportsIsoWeekRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
}

DateTimeRange reportsFullMonthRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
}
