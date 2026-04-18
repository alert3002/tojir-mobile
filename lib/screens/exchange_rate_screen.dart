import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

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
    final s = v.toStringAsFixed(2);
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
        setState(() => history = j.cast<Map<String, dynamic>>());
      } else if (j is Map) {
        final list = (j['results'] is List) ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList() : <Map<String, dynamic>>[];
        final cr = _asDouble(j['current_rate']);
        setState(() {
          history = list;
          if (cr != null) currentRate = cr;
        });
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

  String _fmtAt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString().replaceFirst('T', ' ');
    return s.length > 19 ? s.substring(0, 19) : s;
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'course', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final cr = currentRate;

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('Курс валюты', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.trending_up, size: 28, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Текущий курс:', style: TextStyle(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Text(
                              cr != null ? '1 USD = ${cr.toStringAsFixed(2)} TJS' : '—',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      if (loading) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Добавить курс в историю', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: rateCtrl,
                        decoration: const InputDecoration(
                          labelText: '1 USD =',
                          suffixText: 'TJS',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: submitLoading ? null : _addRate,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить'),
                        style: FilledButton.styleFrom(
                          shape: AppShape.roundedRect,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('История курса', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (historyLoading)
                        const SkeletonListBlock(rows: 6)
else if (history.isEmpty)
                        Text('Записей пока нет', style: TextStyle(color: cs.onSurfaceVariant))
                      else
                        ...history.map((r) {
                          final v = _asDouble(r['usd_to_tjs']);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(child: Text(_fmtAt(r['created_at']), style: TextStyle(color: cs.onSurfaceVariant))),
                                Text(v != null ? v.toStringAsFixed(2) : '—', style: const TextStyle(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

