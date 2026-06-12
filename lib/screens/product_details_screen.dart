import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

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

String _formatQty(dynamic val) {
  final n = _asDouble(val);
  if (n == null) return val?.toString() ?? '';
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString().replaceAll(RegExp(r'\.?0+$'), '');
}

String _unitLabel(String? u) => _unitLabels[u ?? ''] ?? u ?? 'шт';

String _fmtQtyUnit(dynamic qty, String? unit) {
  if (qty == null || qty.toString().isEmpty) return '—';
  return '${_formatQty(qty)} ${_unitLabel(unit)}';
}

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  bool loading = true;
  Map<String, dynamic>? data;
  double usdToTjs = 11.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final api = context.read<ApiClient>();
      final rateRes = await api.get('inventory/rate/');
      if (rateRes.statusCode == 200) {
        final rd = jsonDecode(rateRes.body);
        if (rd is Map && rd['usd_to_tjs'] != null) {
          final n = _asDouble(rd['usd_to_tjs']);
          if (n != null && n > 0) usdToTjs = n;
        }
      }
      final res = await api.get('inventory/products/${widget.productId}/analytics/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        setState(() => data = j is Map<String, dynamic> ? j : null);
      } else {
        final err = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        throw Exception(err is Map ? err['detail']?.toString() ?? 'Не удалось загрузить товар' : 'Ошибка');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => data = null);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic>? get product => data?['product'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get arrivals =>
      (data?['arrivals'] is List) ? (data!['arrivals'] as List).cast<Map<String, dynamic>>() : const [];
  List<Map<String, dynamic>> get outlets =>
      (data?['outlets'] is List) ? (data!['outlets'] as List).cast<Map<String, dynamic>>() : const [];
  List<Map<String, dynamic>> get transfers =>
      (data?['transfers'] is List) ? (data!['transfers'] as List).cast<Map<String, dynamic>>() : const [];

  ({double totalTjs, double totalUsd}) _arrivalsTotal() {
    var tjs = 0.0;
    for (final r in arrivals) {
      final q = _asDouble(r['quantity']) ?? 0;
      final p = _asDouble(r['unit_price']) ?? 0;
      final cur = (r['currency'] ?? 'TJS').toString();
      final sum = q * p;
      tjs += cur == 'TJS' ? sum : sum * usdToTjs;
    }
    return (totalTjs: tjs, totalUsd: tjs / usdToTjs);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = product;
    final model = p?['model']?.toString().trim() ?? '';
    final title = p != null ? '${p['name'] ?? ''}${model.isNotEmpty ? ' $model' : ''}' : 'Товар';
    final unit = (p?['unit'] ?? 'pcs').toString();
    final totals = _arrivalsTotal();
    final lastPurchase = data?['last_purchase'] as Map<String, dynamic>?;

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/warehouse'),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Назад к складу'),
              ),
              const SizedBox(height: 12),
              if (loading)
                const SkeletonListBlock(rows: 8)
              else if (p == null)
                Text('Товар не найден', style: TextStyle(color: cs.onSurfaceVariant))
              else ...[
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tag('SKU: ${p['sku'] ?? '—'}'),
                          if (p['category_name'] != null) _tag(p['category_name'].toString()),
                          if (p['subcategory_name'] != null) _tag(p['subcategory_name'].toString(), color: _blue),
                          if (p['warehouse_name'] != null) _tag('Склад: ${p['warehouse_name']}', color: const Color(0xFF6366F1)),
                        ],
                      ),
                      if ([p['brand'], p['color'], p['memory'], p['ram'], p['size']].any((e) => e != null && '$e'.trim().isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (p['brand'] != null) _tag(p['brand'].toString()),
                            if (p['color'] != null) _tag(p['color'].toString()),
                            if (p['memory'] != null) _tag(p['memory'].toString(), color: _blue),
                            if (p['ram'] != null) _tag(p['ram'].toString(), color: const Color(0xFF6366F1)),
                            if (p['size'] != null) _tag(p['size'].toString(), color: const Color(0xFF8B5CF6)),
                          ],
                        ),
                      ],
                      if (lastPurchase != null && lastPurchase['unit_price'] != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Последняя закупка: ${lastPurchase['unit_price']} ${lastPurchase['currency']} · ${_fmtQtyUnit(lastPurchase['quantity'], lastPurchase['unit']?.toString())} · ${lastPurchase['arrival_date'] ?? ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionTitle('Поступления (история)'),
                if (arrivals.isEmpty)
                  Text('Нет поступлений', style: TextStyle(color: cs.onSurfaceVariant))
                else
                  for (final r in arrivals) ...[
                    const SizedBox(height: 8),
                    _ArrivalCard(record: r, usdToTjs: usdToTjs),
                  ],
                if (totals.totalTjs > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Итого (общая сумма):', style: TextStyle(fontWeight: FontWeight.w800)),
                        Text('${totals.totalTjs.toStringAsFixed(2)} сомон / ≈ ${totals.totalUsd.toStringAsFixed(2)} USD'),
                        Text('по курсу 1 USD = ${usdToTjs.toStringAsFixed(2)} TJS', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _sectionTitle('Остатки по магазинам'),
                if (outlets.isEmpty)
                  Text('—', style: TextStyle(color: cs.onSurfaceVariant))
                else
                  for (final o in outlets) ...[
                    const SizedBox(height: 6),
                    _simpleRow((o['outlet_name'] ?? '—').toString(), _fmtQtyUnit(o['quantity'], unit)),
                  ],
                const SizedBox(height: 16),
                _sectionTitle('Перемещения (магазины ↔ склад)'),
                if (transfers.isEmpty)
                  Text('Нет перемещений', style: TextStyle(color: cs.onSurfaceVariant))
                else
                  for (final t in transfers) ...[
                    const SizedBox(height: 8),
                    _TransferCard(record: t, unit: unit),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _sectionCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: child,
      );

  Widget _tag(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.2)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: color ?? Colors.white.withValues(alpha: 0.9))),
      );

  Widget _simpleRow(String left, String right) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(left)),
            Text(right, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ArrivalCard extends StatelessWidget {
  const _ArrivalCard({required this.record, required this.usdToTjs});
  final Map<String, dynamic> record;
  final double usdToTjs;

  @override
  Widget build(BuildContext context) {
    final q = _asDouble(record['quantity']) ?? 0;
    final p = _asDouble(record['unit_price']) ?? 0;
    final cur = (record['currency'] ?? 'TJS').toString();
    final sum = q * p;
    final sumTjs = cur == 'TJS' ? sum : sum * usdToTjs;
    final sumUsd = sumTjs / usdToTjs;
    final unit = _unitLabel(record['unit']?.toString());

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((record['arrival_date'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _meta('Кол-во', '${_formatQty(record['quantity'])} $unit')),
              Expanded(child: _meta('Закупка', '${record['unit_price']} $cur')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _meta('Поставщик', (record['supplier_name'] ?? '—').toString())),
              Expanded(child: _meta('Состояние', record['condition'] == 'used' ? 'Б/У' : 'Новый')),
            ],
          ),
          const SizedBox(height: 6),
          _meta('Сумма', '${sum.toStringAsFixed(2)} $cur  ≈ ${sumUsd.toStringAsFixed(2)} USD'),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.record, required this.unit});
  final Map<String, dynamic> record;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final created = record['created_at']?.toString();
    String dateStr = '—';
    if (created != null && created.isNotEmpty) {
      try {
        final d = DateTime.parse(created);
        dateStr = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        dateStr = created;
      }
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            '${record['from_outlet_name'] ?? 'Склад'} → ${record['to_outlet_name'] ?? 'Склад'}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text('Кол-во: ${_fmtQtyUnit(record['quantity'], unit)}${(record['note']?.toString().trim().isNotEmpty ?? false) ? ' · ${record['note']}' : ''}'),
        ],
      ),
    );
  }
}
