import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

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

String _firstApiError(Map<String, dynamic> m, {String fallback = 'Ошибка'}) {
  final d = m['detail'];
  if (d is String && d.isNotEmpty) return d;
  return fallback;
}

String _fullName(Map<String, dynamic> r) {
  final fn = (r['first_name'] ?? '').toString().trim();
  final ln = (r['last_name'] ?? '').toString().trim();
  final name = [fn, ln].where((x) => x.isNotEmpty).join(' ');
  return name.isEmpty ? '—' : name;
}

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> employees = const [];
  bool loading = false;

  List<Map<String, dynamic>> warehouses = const [];
  int? warehouseFilter;

  final Set<int> selectedIds = <int>{};

  int? revokingId;
  bool bulkRevokeLoading = false;

  bool get _isPlatform => (context.read<SessionController>().user?['role'] as String?) == 'platform';

  bool get _isBusinessman => (context.read<SessionController>().user?['role'] as String?) == 'businessman';

  bool get _canAddRevoke {
    final u = context.read<SessionController>().user;
    return (u?['role'] as String?) == 'businessman' && u?['warehouse'] != null;
  }

  Future<void> _loadWarehousesIfNeeded() async {
    if (!_isPlatform) return;
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

  Future<void> _loadEmployees() async {
    final u = context.read<SessionController>().user;
    if (u == null) {
      setState(() => employees = const []);
      return;
    }
    setState(() => loading = true);
    final api = context.read<ApiClient>();
    try {
      final q = <String, String>{};
      if (_isPlatform && warehouseFilter != null) q['warehouse'] = warehouseFilter.toString();
      final qs = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final path = 'me/employees/${qs.isEmpty ? '' : '?$qs'}';
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла. Войдите снова.', error: true);
        setState(() {
          employees = const [];
          loading = false;
        });
        return;
      }
      if (res.statusCode != 200) {
        setState(() => employees = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      setState(() => employees = list);
    } catch (_) {
      if (mounted) setState(() => employees = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadWarehousesIfNeeded();
      await _loadEmployees();
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _revoke(Map<String, dynamic> record) async {
    final id = _asInt(record['id']);
    if (id == null) return;
    final phone = (record['phone'] ?? '').toString();
    final name = _fullName(record);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать доступ?'),
        content: Text('$name ($phone) больше не будет иметь доступа к вашему складу.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => revokingId = id);
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('me/employees/$id/revoke/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        final data = _tryJsonMap(res.body);
        throw Exception(_firstApiError(data));
      }
      _snack('Доступ отозван');
      selectedIds.remove(id);
      await _loadEmployees();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => revokingId = null);
    }
  }

  Future<void> _bulkRevoke() async {
    if (selectedIds.isEmpty) {
      _snack('Выберите сотрудников');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать доступ у выбранных?'),
        content: Text('У ${selectedIds.length} сотрудников будет отозван доступ к складу.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => bulkRevokeLoading = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post('me/employees/bulk-revoke/', body: {'ids': selectedIds.toList()});
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) throw Exception(_firstApiError(data));
      _snack((data['detail'] ?? 'Доступ отозван').toString());
      setState(() => selectedIds.clear());
      await _loadEmployees();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => bulkRevokeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    final canView = u != null && canAccessSection(u, 'employees', null);
    if (!canView) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final canManage = _canAddRevoke || _isPlatform;

    String hint;
    if (_isBusinessman) {
      hint =
          'Продавцы, привязанные к вашему складу. Добавить, изменить, просмотр и отзыв доступа — через список и отдельные страницы.';
    } else if (_isPlatform) {
      hint = 'Список продавцов по складу. Выберите склад — отобразятся продавцы этого склада.';
    } else {
      hint = 'Доступ к управлению сотрудниками есть у бизнесменов.';
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadWarehousesIfNeeded();
            await _loadEmployees();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('Сотрудники', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(hint, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35)),
              const SizedBox(height: 12),
              if ((_isBusinessman && u['warehouse'] != null) || _isPlatform) ...[
                if (_isBusinessman) ...[
                  Row(
                    children: [
                      const Text('Продавцы склада: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      Expanded(child: Text((u['warehouse_name'] ?? '—').toString())),
                    ],
                  ),
                ] else ...[
                  DropdownButtonFormField<int>(
                    value: warehouseFilter,
                    decoration: const InputDecoration(
                      labelText: 'Склад',
                      border: OutlineInputBorder(),
                    ),
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
                      _loadEmployees();
                    },
                  ),
                ],
                const SizedBox(height: 12),
              ],
              if (_isPlatform) ...[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/moderators'),
                  child: const Text('Список модераторов'),
                ),
                const SizedBox(height: 12),
              ],
              if (_canAddRevoke) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pushNamed('/moderators'),
                      child: const Text('Модераторы'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pushNamed('/employees/add'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить сотрудника'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selectedIds.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: bulkRevokeLoading ? null : _bulkRevoke,
                        icon: const Icon(Icons.person_remove_alt_1_outlined, size: 18),
                        label: Text('Отозвать (${selectedIds.length})'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_isBusinessman && u['warehouse'] == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Укажите склад в профиле, чтобы добавлять сотрудников.',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                ),
              const SizedBox(height: 8),
              if (loading) const SkeletonListBlock(rows: 6)
else if (employees.isEmpty)
                Text(
                  _canAddRevoke ? 'Нет сотрудников. Нажмите «Добавить сотрудника».' : 'Нет данных.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
              else
                ...employees.map((r) {
                  final id = _asInt(r['id']);
                  final phone = (r['phone'] ?? '—').toString();
                  final isActive = r['is_active'] == true;
                  final joined = (r['date_joined'] ?? '').toString();
                  final joinedShort = joined.isNotEmpty ? joined.split('T').first : '—';
                  final selected = id != null && selectedIds.contains(id);
                  const compactConstraints = BoxConstraints.tightFor(width: 36, height: 36);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: AppShape.br,
                      onTap: id == null ? null : () => Navigator.of(context).pushNamed('/employees/$id'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_canAddRevoke)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Checkbox(
                                  value: selected,
                                  onChanged: id == null
                                      ? null
                                      : (v) {
                                          setState(() {
                                            if (v == true) {
                                              selectedIds.add(id);
                                            } else {
                                              selectedIds.remove(id);
                                            }
                                          });
                                        },
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(phone, style: const TextStyle(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 2),
                                  Text(_fullName(r), style: TextStyle(color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 2),
                                  Text('Роль: Продавец', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  Text('Статус: ${isActive ? 'Активен' : 'Неактивен'}',
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  Text('Добавлен: $joinedShort',
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (canManage && id != null)
                              Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_red_eye_outlined),
                                    tooltip: 'Просмотр',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: compactConstraints,
                                    onPressed: () => Navigator.of(context).pushNamed('/employees/$id'),
                                  ),
                                  if (_canAddRevoke) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Изменить',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: compactConstraints,
                                      onPressed: () => Navigator.of(context).pushNamed('/employees/$id/edit'),
                                    ),
                                    IconButton(
                                      icon: revokingId == id
                                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.person_remove_alt_1_outlined),
                                      tooltip: 'Отозвать доступ',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: compactConstraints,
                                      onPressed: revokingId == id ? null : () => _revoke(r),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

