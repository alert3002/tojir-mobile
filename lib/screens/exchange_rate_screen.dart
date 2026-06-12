import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_brand.dart';
import '../utils/number_format.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _historyPageSize = 20;

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

Map<String, dynamic> _tryJsonMap(String body) {
  try {
    final j = jsonDecode(body.isEmpty ? '{}' : body);
    return j is Map<String, dynamic> ? j : {};
  } catch (_) {
    return {};
  }
}

String _firstApiError(Map<String, dynamic> m, {String fallback = 'Ошибка'}) {
  final d = m['detail'];
  if (d is String && d.isNotEmpty) return d;
  final v = m['usd_to_tjs'];
  if (v is List && v.isNotEmpty) return v.first.toString();
  return fallback;
}

String _fmtRate(num? v) {
  if (v == null) return '—';
  return formatRuMoney(v, fractionDigits: 2);
}

String _fmtDateRu(dynamic raw) {
  if (raw == null) return '—';
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return raw.toString();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  final sec = d.second.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}, $hh:$min:$sec';
}

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({super.key});

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  bool loading = false;
  bool historyLoading = false;
  bool submitLoading = false;

  double? currentRate;
  List<Map<String, dynamic>> history = const [];
  int historyPage = 1;

  final TextEditingController rateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCurrent();
      await _loadHistory();
      _syncInput();
    });
  }

  @override
  void dispose() {
    rateCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  void _syncInput() {
    final v = currentRate;
    if (v == null) return;
    final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
    if (rateCtrl.text != s) {
      rateCtrl.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    }
  }

  Future<void> _loadCurrent() async {
    setState(() => loading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => currentRate = null);
        return;
      }
      final d = _tryJsonMap(res.body);
      final v = _asDouble(d['usd_to_tjs']);
      setState(() => currentRate = v);
      _syncInput();
    } catch (_) {
      if (mounted) setState(() => currentRate = null);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => historyLoading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/rate/history/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => history = const []);
        return;
      }
      final j = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (j is List) {
        setState(() {
          history = j.cast<Map<String, dynamic>>();
          historyPage = 1;
        });
      } else if (j is Map) {
        final list = (j['results'] is List)
            ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        final cr = _asDouble(j['current_rate']);
        setState(() {
          history = list;
          historyPage = 1;
          if (cr != null) currentRate = cr;
        });
        _syncInput();
      } else {
        setState(() => history = const []);
      }
    } catch (_) {
      if (mounted) setState(() => history = const []);
    } finally {
      if (mounted) setState(() => historyLoading = false);
    }
  }

  Future<void> _addRate() async {
    final v = double.tryParse(rateCtrl.text.replaceAll(',', '.'));
    if (v == null || v <= 0) {
      _snack('Введите курс > 0', error: true);
      return;
    }
    setState(() => submitLoading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.post('inventory/rate/history/', body: {'usd_to_tjs': v});
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) throw Exception(_firstApiError(data));
      setState(() {
        history = [data, ...history];
        historyPage = 1;
        currentRate = _asDouble(data['usd_to_tjs']) ?? currentRate;
      });
      _syncInput();
      _snack('Курс добавлен в историю');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => submitLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'course', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final cr = currentRate;
    final totalPages = history.isEmpty ? 1 : (history.length / _historyPageSize).ceil();
    final pageSlice = history.skip((historyPage - 1) * _historyPageSize).take(_historyPageSize).toList();

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadCurrent();
            await _loadHistory();
            _syncInput();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            children: [
              Text('Курс валюты', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.25)),
              const SizedBox(height: 8),
              _CourseCard(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: [
                            AppBrand.primaryBlue.withValues(alpha: 0.22),
                            const Color(0xFF22C55E).withValues(alpha: 0.18),
                          ],
                        ),
                      ),
                      child: Icon(Icons.trending_up_rounded, size: 22, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                          children: [
                            const TextSpan(text: 'Текущий курс: '),
                            TextSpan(
                              text: cr != null ? '1 USD = ${_fmtRate(cr)} TJS' : '—',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (loading) SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _CourseCard(
                title: 'Добавить курс в историю',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('* ', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                        Text('1 USD =', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: rateCtrl,
                      style: TextStyle(fontSize: 15, color: cs.onSurface),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        suffixText: 'TJS',
                        suffixStyle: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: submitLoading ? null : _addRate,
                        icon: submitLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Добавить', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppBrand.primaryBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _CourseCard(
                title: 'История курса',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (historyLoading)
                      const SkeletonListBlock(rows: 5)
                    else if (history.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Записей пока нет', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text('Дата', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
                            Text('1 USD = TJS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      for (final r in pageSlice)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(_fmtDateRu(r['created_at']), style: TextStyle(fontSize: 13, color: cs.onSurface, height: 1.35)),
                              ),
                              Text(
                                _fmtRate(_asDouble(r['usd_to_tjs'])),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurface),
                              ),
                            ],
                          ),
                        ),
                      if (history.length > _historyPageSize) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: historyPage > 1 ? () => setState(() => historyPage--) : null,
                              icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            ),
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppBrand.primaryBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('$historyPage', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: historyPage < totalPages ? () => setState(() => historyPage++) : null,
                              icon: const Icon(Icons.chevron_right_rounded, size: 20),
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

class _CourseCard extends StatelessWidget {
  const _CourseCard({this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: AppBrand.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25))),
              ),
              child: Text(title!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: child,
          ),
        ],
      ),
    );
  }
}
