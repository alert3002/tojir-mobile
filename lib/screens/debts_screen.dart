import 'dart:async';
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
  var intPart = s.substring(0, dot);
  final dec = s.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('\u00A0');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}${buf.toString()}$dec';
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

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

String _fmtYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _firstApiError(Map<String, dynamic> m) {
  final d = m['detail'];
  if (d is String && d.isNotEmpty) return d;
  for (final key in ['amount', 'client_phone', 'note', 'checkout_sms_verification_id', 'sale_outlet', 'warehouse']) {
    final v = m[key];
    if (v is List && v.isNotEmpty) return v.first.toString();
  }
  return 'Ошибка';
}

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

String _sliceDate(dynamic v) {
  if (v == null) return '—';
  final s = v.toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _sliceCreated(dynamic v) {
  if (v == null) return '—';
  final s = v.toString().replaceFirst('T', ' ');
  return s.length > 19 ? s.substring(0, 19) : s;
}

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  List<Map<String, dynamic>> debts = const [];
  bool loading = false;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';
  DateTimeRange? dateRange;
  String? datePresetKey;
  bool showTrash = false;
  List<Map<String, dynamic>> outlets = const [];
  double? usdToTjs;
  int? deletingId;
  int? reminderLoadingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRate();
      await _loadOutlets();
      await _loadDebts();
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _isSeller => (_user?['role'] as String?) == 'seller';
  bool get _isClient => (_user?['role'] as String?) == 'client';

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

  Future<void> _loadOutlets() async {
    final u = _user;
    final tokenUser = u;
    if (tokenUser == null || _isClient) {
      if (mounted) setState(() => outlets = const []);
      return;
    }
    final api = context.read<ApiClient>();
    final isSellerRole = (tokenUser['role'] as String?) == 'seller';
    final path = isSellerRole
        ? 'inventory/outlets'
        : 'inventory/outlets${tokenUser['warehouse'] != null ? '?warehouse=${tokenUser['warehouse']}' : ''}';
    try {
      final res = await api.get(path);
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

  Future<void> _loadDebts() async {
    final api = context.read<ApiClient>();
    setState(() => loading = true);
    try {
      final q = <String, String>{};
      final s = search.trim();
      if (s.isNotEmpty) q['search'] = s;
      if (dateRange != null) {
        q['date_from'] = _fmtYmd(dateRange!.start);
        q['date_to'] = _fmtYmd(dateRange!.end);
      }
      if (showTrash) q['trash'] = '1';
      final qs = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final path = 'inventory/debts/${qs.isEmpty ? '' : '?$qs'}';
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла или вход недействителен. Войдите снова.');
        setState(() {
          debts = const [];
          loading = false;
        });
        return;
      }
      if (res.statusCode != 200) {
        setState(() => debts = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List
          ? j.cast<Map<String, dynamic>>()
          : (j is Map && j['results'] is List)
              ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
              : <Map<String, dynamic>>[];
      setState(() => debts = list);
    } catch (_) {
      if (mounted) setState(() => debts = const []);
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
    await _loadDebts();
  }

  void _clearDateRange() {
    setState(() {
      dateRange = null;
      datePresetKey = null;
    });
    _loadDebts();
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
    _loadDebts();
  }

  Future<void> _openAdd() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _AddDebtSheet(
        outlets: outlets,
        userWarehouse: _user?['warehouse'],
        usdToTjs: usdToTjs,
        onSaved: () {
          Navigator.pop(ctx);
          _loadDebts();
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
      builder: (ctx) => _EditDebtSheet(record: record, usdToTjs: usdToTjs, onSaved: () {
        Navigator.pop(ctx);
        _loadDebts();
      }),
    );
  }

  Future<void> _openPayment(Map<String, dynamic> record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _PaymentSheet(record: record, usdToTjs: usdToTjs, onSaved: () {
        Navigator.pop(ctx);
        _loadDebts();
      }),
    );
  }

  Future<void> _openHistory(Map<String, dynamic> record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      builder: (ctx) => _HistorySheet(record: record, usdToTjs: usdToTjs),
    );
  }

  Future<void> _delete(Map<String, dynamic> record, {required bool permanent}) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    final name = (record['debtor_name'] ?? '—').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? 'Удалить долг навсегда?' : 'Переместить долг в корзину?'),
        content: Text(
          permanent
              ? 'Долг «$name» будет удалён безвозвратно.'
              : '$name: ${_formatMoneyRu(_asDouble(record['amount']) ?? 0)} ${record['currency'] ?? ''}',
        ),
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
      final path = 'inventory/debts/$id/${permanent ? '?force=1' : ''}';
      final res = await api.delete(path);
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) throw Exception();
      _snack(permanent ? 'Долг удалён навсегда' : 'Долг в корзине');
      await _loadDebts();
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
      final res = await api.patch('inventory/debts/$id/', body: {'is_deleted': false});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception();
      _snack('Долг восстановлен');
      await _loadDebts();
    } catch (_) {
      _snack('Не удалось восстановить', error: true);
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    setState(() => reminderLoadingId = id);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post('inventory/debts/$id/send-reminder/', body: {});
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode == 429) {
        _snack(data['detail']?.toString() ?? 'Повторная отправка возможна через 72 часа');
        await _loadDebts();
        return;
      }
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      _snack('SMS клиенту отправлено; склад получил уведомление');
      await _loadDebts();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => reminderLoadingId = null);
    }
  }

  String _reminderTooltip(Map<String, dynamic> record) {
    if ((record['client_phone'] as String?)?.trim().isEmpty ?? true) {
      return 'Нет телефона клиента — укажите в «Изменить»';
    }
    if (record['debt_reminder_can_send'] == false && record['debt_reminder_next_at'] != null) {
      final s = record['debt_reminder_next_at'].toString().replaceFirst('T', ' ');
      return 'Следующая отправка: ${s.length > 16 ? s.substring(0, 16) : s}';
    }
    return 'Отправить SMS: остаток долга, магазин, причина (по тарифу — не чаще 1 раза в 72 ч)';
  }

  Widget _actionsRow(Map<String, dynamic> record, {required bool clientOwes}) {
    if (_isClient) return const SizedBox.shrink();
    final id = _asInt(record['id']);
    final remaining = _asDouble(record['amount_remaining']) ?? _asDouble(record['amount']) ?? 0;
    const compactConstraints = BoxConstraints.tightFor(width: 36, height: 36);
    if (showTrash) {
      return Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Восстановить',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compactConstraints,
            onPressed: () => _restore(record),
          ),
          IconButton(
            icon: deletingId == id ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_forever),
            tooltip: 'Удалить навсегда',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compactConstraints,
            onPressed: deletingId == id ? null : () => _delete(record, permanent: true),
          ),
        ],
      );
    }
    final phoneOk = (record['client_phone'] as String?)?.trim().isNotEmpty ?? false;
    final canRemind = phoneOk && record['debt_reminder_can_send'] != false;
    return Wrap(
      spacing: 0,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Изменить',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compactConstraints,
          onPressed: () => _openEdit(record),
        ),
        IconButton(
          icon: deletingId == id ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
          tooltip: 'Удалить',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compactConstraints,
          onPressed: deletingId == id ? null : () => _delete(record, permanent: false),
        ),
        IconButton(
          icon: const Icon(Icons.payments_outlined),
          tooltip: 'Оплата',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compactConstraints,
          onPressed: remaining <= 0 ? null : () => _openPayment(record),
        ),
        if (clientOwes)
          IconButton(
            icon: reminderLoadingId == id
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sms_outlined),
            tooltip: _reminderTooltip(record),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compactConstraints,
            onPressed: (reminderLoadingId == id || !canRemind) ? null : () => _sendReminder(record),
          ),
      ],
    );
  }

  Widget _debtTile(Map<String, dynamic> r, {required bool weOwe}) {
    final cs = Theme.of(context).colorScheme;
    final amt = _asDouble(r['amount']);
    final rem = _asDouble(r['amount_remaining']) ?? amt;
    final cur = (r['currency'] ?? 'TJS').toString();
    final signColor = weOwe ? cs.error : cs.primary;
    final sign = weOwe ? '−' : '+';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openHistory(r),
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
                          (r['debtor_name'] ?? r['debtor_display'] ?? '—').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (!weOwe && (r['client_phone'] as String?)?.isNotEmpty == true)
                          Text(r['client_phone'] as String, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (!weOwe && r['sale_batch_id'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Chip(
                              label: const Text('Из продажи', style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_isSeller && !_isClient)
                    Text(
                      (r['warehouse_name'] ?? '—').toString(),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              if (!weOwe && !_isSeller) ...[
                const SizedBox(height: 4),
                Text('Магазин: ${r['sale_outlet_name'] ?? '—'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                if ((r['sold_by_display'] as String?)?.isNotEmpty ?? false)
                  Text('Продавец: ${r['sold_by_display']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Сумма', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      Text(
                        amt != null ? '$sign${_formatMoneyRu(amt)} $cur' : '—',
                        style: TextStyle(fontWeight: FontWeight.w600, color: signColor),
                      ),
                      if (amt != null) _fxLine(amt, cur, usdToTjs, cs) ?? const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Остаток', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      Text(
                        rem != null ? '$sign${_formatMoneyRu(rem)} $cur' : '—',
                        style: TextStyle(fontWeight: FontWeight.w600, color: signColor),
                      ),
                      if (rem != null) _fxLine(rem, cur, usdToTjs, cs) ?? const SizedBox.shrink(),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Срок: ${_sliceDate(r['due_date'])} · Создано: ${_sliceCreated(r['created_at'])}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              if ((r['note'] as String?)?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(r['note'] as String, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.9))),
                ),
              _actionsRow(r, clientOwes: !weOwe),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Map<String, dynamic>> items,
    required bool weOwe,
    Color? tint,
    Color? border,
    Widget? titleTrailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppShape.br,
        border: Border.all(color: border ?? cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                ?titleTrailing,
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const SkeletonListBlock(rows: 6)
else if (items.isEmpty)
              Text(weOwe ? 'Нет записей.' : 'Нет записей. Долги с продажи создаются автоматически; «Добавить» — вручную.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else
              ...items.map((e) => _debtTile(e, weOwe: weOwe)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'debts', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final weOwe = debts.where((d) => d['debt_type'] == 'we_owe').toList();
    final clientOwes = debts.where((d) => d['debt_type'] == 'client_owes').toList();

    String title;
    if (_isClient) {
      title = 'Мои долги';
    } else if (_isSeller) {
      title = 'Долги (Насия)';
    } else {
      title = 'Долги (Насия)';
    }

    String subtitle;
    if (_isClient) {
      subtitle = 'Открытые долги по вашему номеру телефона в магазинах (насия и частичная оплата с продажи).';
    } else if (_isSeller) {
      subtitle =
          'Записи появляются автоматически при продаже с оплатой Насия или Частично (имя клиента, телефон, товары и сумма). Раздел «Мы должим» для продавца скрыт.';
    } else {
      subtitle =
          '«Мы должим» — из поступления «в долг». «Клиент должин» — вручную или автоматически при продаже с оплатой Насия или Частично.';
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRate();
            await _loadOutlets();
            await _loadDebts();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35)),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Поиск по контрагенту',
                  border: OutlineInputBorder(borderRadius: AppShape.br),
                  isDense: true,
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () {
                    search = searchCtrl.text;
                    _loadDebts();
                  }),
                ),
                onSubmitted: (_) {
                  search = searchCtrl.text;
                  _loadDebts();
                },
              ),
              const SizedBox(height: 8),
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
              if (!_isClient) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(value: showTrash, onChanged: (v) {
                      setState(() => showTrash = v);
                      _loadDebts();
                    }),
                    Text('В корзине', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (!_isSeller && !_isClient)
                _sectionCard(
                  title: 'Мы должим',
                  items: weOwe,
                  weOwe: true,
                  tint: cs.error.withValues(alpha: 0.08),
                  border: cs.error.withValues(alpha: 0.35),
                ),
              _sectionCard(
                title: _isClient ? 'Долги' : 'Клиент должин',
                items: clientOwes,
                weOwe: false,
                tint: cs.primary.withValues(alpha: 0.08),
                border: cs.primary.withValues(alpha: 0.35),
                titleTrailing: (!showTrash && !_isClient)
                    ? FilledButton.icon(
                        onPressed: outlets.isEmpty ? null : _openAdd,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      )
                    : null,
              ),
              if (!_isClient && outlets.isEmpty && !loading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Нет магазинов для вашего склада — создайте точку в разделе «Магазины».',
                      style: TextStyle(color: cs.tertiary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Add debt (SMS + verify) ---

class _AddDebtSheet extends StatefulWidget {
  const _AddDebtSheet({
    required this.outlets,
    required this.userWarehouse,
    required this.usdToTjs,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> outlets;
  final dynamic userWarehouse;
  final double? usdToTjs;
  final VoidCallback onSaved;

  @override
  State<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<_AddDebtSheet> {
  final debtorCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  late final TextEditingController phoneCtrl;
  String phoneSuffix = '';
  String currency = 'TJS';
  int? outletId;
  DateTime? dueDate;

  String? verificationId;
  bool smsVerified = false;
  String smsCode = '';
  bool sendingSms = false;
  bool verifyingSms = false;
  bool saving = false;
  Timer? cooldownTimer;
  int cooldownSec = 0;

  @override
  void initState() {
    super.initState();
    phoneCtrl = TextEditingController();
    if (widget.outlets.length == 1) {
      outletId = _asInt(widget.outlets.first['id']);
    }
  }

  @override
  void dispose() {
    debtorCtrl.dispose();
    noteCtrl.dispose();
    amountCtrl.dispose();
    phoneCtrl.dispose();
    cooldownTimer?.cancel();
    super.dispose();
  }

  void _resetSms() {
    cooldownTimer?.cancel();
    cooldownTimer = null;
    setState(() {
      verificationId = null;
      smsVerified = false;
      smsCode = '';
      cooldownSec = 0;
    });
  }

  void _onFieldsChanged() {
    _resetSms();
  }

  void _startCooldown() {
    cooldownTimer?.cancel();
    final end = DateTime.now().add(const Duration(seconds: 60));
    void tick() {
      if (!mounted) return;
      final left = end.difference(DateTime.now()).inSeconds;
      setState(() => cooldownSec = left > 0 ? left : 0);
      if (left <= 0) {
        cooldownTimer?.cancel();
        cooldownTimer = null;
      }
    }

    tick();
    cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  bool get phoneOk => phoneSuffix.replaceAll(RegExp(r'\D'), '').length == 9;

  Future<void> _requestSms() async {
    final digits = phoneSuffix.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите номер после +992 (9 цифр)')));
      return;
    }
    if (debtorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите имя')));
      return;
    }
    if (outletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите магазин')));
      return;
    }
    final note = noteCtrl.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заполните примечание для SMS')));
      return;
    }
    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите сумму долга')));
      return;
    }

    setState(() => sendingSms = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/debts/checkout-sms/request/',
        body: {
          'phone': '992$digits',
          'total_tjs': amount,
          'cart_label': debtorCtrl.text.trim().length > 200 ? debtorCtrl.text.trim().substring(0, 200) : debtorCtrl.text.trim(),
          'comment': note.length > 500 ? note.substring(0, 500) : note,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      final vid = data['verification_id'];
      setState(() {
        verificationId = vid?.toString();
        smsVerified = false;
        smsCode = '';
      });
      _startCooldown();
      if (data['debug_code'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Код (DEBUG): ${data['debug_code']}')));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['sms_sent'] == true ? 'SMS отправлено' : (data['warning']?.toString() ?? 'SMS не отправлено — проверьте OsonSMS')),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => sendingSms = false);
    }
  }

  Future<void> _verifySms() async {
    final vid = verificationId;
    final c = smsCode.replaceAll(RegExp(r'\D'), '');
    if (vid == null || c.isEmpty) return;
    setState(() => verifyingSms = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/debts/checkout-sms/verify/',
        body: {'verification_id': vid, 'code': c},
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(_firstApiError(data));
      }
      setState(() => smsVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код подтверждён — можно сохранить долг')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => verifyingSms = false);
    }
  }

  Future<void> _save() async {
    final u = context.read<SessionController>().user;
    final digits = phoneSuffix.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9 || !smsVerified || verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите телефон (9 цифр) и подтвердите код из SMS')));
      return;
    }
    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0 || outletId == null) return;

    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final body = <String, dynamic>{
        'debtor_display': debtorCtrl.text.trim(),
        'client_phone': '992$digits',
        'amount': amount,
        'currency': currency,
        'due_date': dueDate != null ? _fmtYmd(dueDate!) : null,
        'note': noteCtrl.text.trim(),
        'sale_outlet': outletId,
        'checkout_sms_verification_id': verificationId,
      };
      if (u?['warehouse'] != null) body['warehouse'] = u!['warehouse'];

      final res = await api.post('inventory/debts/', body: body);
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(_firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Долг клиента добавлен')));
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
    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text('Добавить долг клиента', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Как при продаже в насию: телефон обязателен, текст примечания уходит в SMS клиенту, затем код подтверждения.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: debtorCtrl,
              decoration: const InputDecoration(labelText: 'Клиент / контрагент', border: OutlineInputBorder()),
              onChanged: (_) => _onFieldsChanged(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: outletId,
              decoration: const InputDecoration(labelText: 'Магазин *', border: OutlineInputBorder()),
              items: [
                for (final o in widget.outlets)
                  if (_asInt(o['id']) != null)
                    DropdownMenuItem<int>(
                      value: _asInt(o['id'])!,
                      child: Text((o['name'] ?? 'Магазин ${o['id']}').toString()),
                    ),
              ],
              onChanged: widget.outlets.length == 1
                  ? null
                  : (v) {
                      setState(() => outletId = v);
                      _onFieldsChanged();
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: InputDecoration(
                labelText: 'Телефон *',
                prefixText: '+992 ',
                border: const OutlineInputBorder(),
                errorText: phoneSuffix.isNotEmpty && !phoneOk ? 'Нужно 9 цифр' : null,
              ),
              keyboardType: TextInputType.phone,
              onChanged: (raw) {
                var d = raw.replaceAll(RegExp(r'\D'), '');
                if (d.startsWith('992')) d = d.substring(3);
                if (d.length > 9) d = d.substring(0, 9);
                if (phoneCtrl.text != d) {
                  phoneCtrl.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                }
                setState(() => phoneSuffix = d);
                _onFieldsChanged();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Сумма *', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _onFieldsChanged(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: currency,
              decoration: const InputDecoration(labelText: 'Валюта', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'TJS', child: Text('TJS')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => currency = v);
                _onFieldsChanged();
              },
            ),
            if (amount != null && amount > 0) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _fxLine(amount, currency, widget.usdToTjs, cs) ?? const SizedBox.shrink(),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срок (необязательно)'),
              subtitle: Text(dueDate == null ? 'Не выбрано' : _fmtYmd(dueDate!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(DateTime.now().year + 5),
                  initialDate: dueDate ?? DateTime.now(),
                );
                if (d != null) {
                  setState(() => dueDate = d);
                  _onFieldsChanged();
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Примечание для SMS *',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              maxLength: 500,
              onChanged: (_) => _onFieldsChanged(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: (sendingSms || cooldownSec > 0) ? null : _requestSms,
                  child: Text(cooldownSec > 0 ? 'Повторить через $cooldownSec с' : 'Отправить SMS'),
                ),
                if (verificationId != null) ...[
                  SizedBox(
                    width: 140,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Код из SMS', isDense: true, border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final d = v.replaceAll(RegExp(r'\D'), '');
                        setState(() => smsCode = d.length > 8 ? d.substring(0, 8) : d);
                      },
                    ),
                  ),
                  OutlinedButton(onPressed: verifyingSms ? null : _verifySms, child: const Text('Подтвердить код')),
                ],
              ],
            ),
            if (smsVerified) ...[
              const SizedBox(height: 8),
              Text('✓ Код подтверждён', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: (saving || !smsVerified || !phoneOk) ? null : _save,
                    child: saving ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Edit ---

class _EditDebtSheet extends StatefulWidget {
  const _EditDebtSheet({required this.record, required this.usdToTjs, required this.onSaved});

  final Map<String, dynamic> record;
  final double? usdToTjs;
  final VoidCallback onSaved;

  @override
  State<_EditDebtSheet> createState() => _EditDebtSheetState();
}

class _EditDebtSheetState extends State<_EditDebtSheet> {
  late final TextEditingController debtorCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;
  String currency = 'TJS';
  DateTime? dueDate;
  bool saving = false;

  bool get _weOwe => widget.record['debt_type'] == 'we_owe';

  @override
  void initState() {
    super.initState();
    debtorCtrl = TextEditingController(text: (widget.record['debtor_display'] ?? widget.record['debtor_name'] ?? '').toString());
    phoneCtrl = TextEditingController(text: (widget.record['client_phone'] ?? '').toString());
    amountCtrl = TextEditingController(text: (_asDouble(widget.record['amount']) ?? 0).toString());
    noteCtrl = TextEditingController(text: (widget.record['note'] ?? '').toString());
    currency = (widget.record['currency'] ?? 'TJS').toString();
    final dd = widget.record['due_date'];
    if (dd != null) {
      final s = dd.toString();
      if (s.length >= 10) {
        dueDate = DateTime.tryParse(s.substring(0, 10));
      }
    }
  }

  @override
  void dispose() {
    debtorCtrl.dispose();
    phoneCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _asInt(widget.record['id']);
    if (id == null) return;
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final Map<String, dynamic> body;
      if (_weOwe) {
        body = {
          'note': noteCtrl.text.trim(),
          'due_date': dueDate != null ? _fmtYmd(dueDate!) : null,
        };
      } else {
        final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
        if (amt == null || amt <= 0) throw Exception('Укажите сумму');
        body = {
          'debtor_display': debtorCtrl.text.trim(),
          'client_phone': phoneCtrl.text.trim(),
          'amount': amt,
          'currency': currency,
          'due_date': dueDate != null ? _fmtYmd(dueDate!) : null,
          'note': noteCtrl.text.trim(),
        };
      }
      final res = await api.patch('inventory/debts/$id/', body: body);
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) {
        throw Exception(data['detail']?.toString() ?? _firstApiError(data));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
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
    final title = _weOwe ? 'Изменить долг (мы должим)' : 'Изменить долг клиента';

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_weOwe) ...[
              TextField(controller: debtorCtrl, decoration: const InputDecoration(labelText: 'Клиент', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Телефон', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Сумма', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              Builder(builder: (ctx) {
                final a = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: a != null && a > 0 ? (_fxLine(a, currency, widget.usdToTjs, cs) ?? const SizedBox.shrink()) : const SizedBox.shrink(),
                );
              }),
              const SizedBox(height: 12),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срок'),
              subtitle: Text(dueDate == null ? 'Не выбрано' : _fmtYmd(dueDate!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(DateTime.now().year + 5),
                  initialDate: dueDate ?? DateTime.now(),
                );
                if (d != null) setState(() => dueDate = d);
              },
            ),
            const SizedBox(height: 8),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Примечание', border: OutlineInputBorder()), maxLines: 3),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: saving ? null : _save,
                    child: saving ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Payment ---

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.record, required this.usdToTjs, required this.onSaved});

  final Map<String, dynamic> record;
  final double? usdToTjs;
  final VoidCallback onSaved;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;
  DateTime paidAt = DateTime.now();
  bool saving = false;

  double get _max => _asDouble(widget.record['amount_remaining']) ?? _asDouble(widget.record['amount']) ?? 0;

  @override
  void initState() {
    super.initState();
    final m = _max;
    amountCtrl = TextEditingController(text: m > 0 ? m.toString() : '0');
    noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPaidAt() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime(paidAt.year, paidAt.month, paidAt.day),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(paidAt));
    if (t == null || !mounted) return;
    setState(() {
      paidAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    final id = _asInt(widget.record['id']);
    if (id == null) return;
    final amt = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (amt == null || amt <= 0 || amt > _max) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сумма от 0.01 до ${_formatMoneyRu(_max)}')));
      return;
    }
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/debts/$id/payments/',
        body: {
          'amount': amt,
          'note': noteCtrl.text.trim(),
          'paid_at': paidAt.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = (data['amount'] is List && (data['amount'] as List).isNotEmpty)
            ? (data['amount'] as List).first.toString()
            : _firstApiError(data);
        throw Exception(msg);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оплата записана')));
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
    final cur = (widget.record['currency'] ?? 'TJS').toString();

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 12),
            const Text('Оплата (частичная или полная)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Остаток: ${_formatMoneyRu(_max)} $cur',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            _fxLine(_max, cur, widget.usdToTjs, cs) ?? const SizedBox.shrink(),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата и время'),
              subtitle: Text('${paidAt.day.toString().padLeft(2, '0')}.${paidAt.month.toString().padLeft(2, '0')}.${paidAt.year} '
                  '${paidAt.hour.toString().padLeft(2, '0')}:${paidAt.minute.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.schedule),
              onTap: _pickPaidAt,
            ),
            TextField(
              controller: amountCtrl,
              decoration: InputDecoration(labelText: 'Сумма оплаты (макс. ${_formatMoneyRu(_max)})', border: const OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Примечание', border: OutlineInputBorder()), maxLines: 2),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: saving ? null : _save,
                    child: saving ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Записать оплату'),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- History ---

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.record, required this.usdToTjs});

  final Map<String, dynamic> record;
  final double? usdToTjs;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<Map<String, dynamic>> payments = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _asInt(widget.record['id']);
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final api = context.read<ApiClient>();
      final res = await api.get('inventory/debts/$id/payments/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          payments = const [];
          loading = false;
        });
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List
          ? j.cast<Map<String, dynamic>>()
          : (j is Map && j['results'] is List)
              ? (j['results'] as List).whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList()
              : <Map<String, dynamic>>[];
      setState(() {
        payments = list;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          payments = const [];
          loading = false;
        });
      }
    }
  }

  String _fmtPaid(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.replaceFirst('T', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.record;
    final weOwe = r['debt_type'] == 'we_owe';
    final sign = weOwe ? '−' : '+';
    final cur = (r['currency'] ?? 'TJS').toString();
    final amt = _asDouble(r['amount']);
    final rem = _asDouble(r['amount_remaining']) ?? amt;
    final paid = _asDouble(r['total_paid']) ?? 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: AppShape.sheetHandle(cs.outlineVariant))),
            const SizedBox(height: 8),
            Text('Долг: ${r['debtor_name'] ?? '—'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  _line('Сумма долга', '$sign${_formatMoneyRu(amt ?? 0)} $cur', fx: _fxLine(amt, cur, widget.usdToTjs, cs)),
                  _line('Остаток', '$sign${_formatMoneyRu(rem ?? 0)} $cur', fx: _fxLine(rem, cur, widget.usdToTjs, cs)),
                  _line('Оплачено', '${_formatMoneyRu(paid)} $cur', fx: _fxLine(paid, cur, widget.usdToTjs, cs)),
                  const SizedBox(height: 8),
                  Text('Дата: ${_sliceCreated(r['created_at'])}', style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  const Text('История оплат', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (loading) const SkeletonListBlock(rows: 4)
else if (payments.isEmpty)
                    Text('Оплат нет.', style: TextStyle(color: cs.onSurfaceVariant))
                  else
                    ...payments.map((p) {
                      final pa = _asDouble(p['amount']);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(_fmtPaid(p['paid_at'])),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_formatMoneyRu(pa ?? 0)} $cur'),
                              if (pa != null) _fxLine(pa, cur, widget.usdToTjs, cs) ?? const SizedBox.shrink(),
                              if ((p['note'] as String?)?.isNotEmpty ?? false) Text(p['note'] as String),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Widget? fx}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ?fx,
        ],
      ),
    );
  }
}
