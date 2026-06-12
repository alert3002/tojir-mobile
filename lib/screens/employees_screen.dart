import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import 'employee_perms.dart';

const _employeesMobilePageSize = 12;
const _cardBg = Color(0xFF1A2438);
const _blue = Color(0xFF2563EB);
const _contextBlue = Color(0xFFBFDBFE);
const _activeGreen = Color(0xFF52C41A);

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

String _employeeDisplayName(Map<String, dynamic> r) {
  final fn = (r['first_name'] ?? '').toString().trim();
  final ln = (r['last_name'] ?? '').toString().trim();
  final name = [fn, ln].where((x) => x.isNotEmpty).join(' ');
  return name.isEmpty ? 'Без имени' : name;
}

String _formatPhone(dynamic phone) {
  if (phone == null || phone.toString().isEmpty) return '—';
  final digits = phone.toString().replaceAll(RegExp(r'\D'), '');
  if (digits.length == 9) return '+992 $digits';
  if (digits.length == 12 && digits.startsWith('992')) return '+992 ${digits.substring(3)}';
  return phone.toString();
}

String _formatJoinedDate(dynamic v) {
  if (v == null) return '—';
  final d = DateTime.tryParse(v.toString());
  if (d == null) return v.toString().split('T').first;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> employees = const [];
  List<Map<String, dynamic>> warehouses = const [];
  List<Map<String, dynamic>> outlets = const [];

  bool loading = false;
  int? warehouseFilter;
  String search = '';
  final TextEditingController searchCtrl = TextEditingController();
  int mobilePage = 1;
  int? revokingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadWarehousesIfNeeded();
      await _loadOutlets();
      await _loadEmployees();
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _isPlatform => (_user?['role'] as String?) == 'platform';

  bool get _isBusinessman => (_user?['role'] as String?) == 'businessman';

  bool get _canAddRevoke => _isBusinessman && _user?['warehouse'] != null;

  List<Map<String, dynamic>> get _filteredEmployees {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return employees;
    return employees.where((e) {
      final name = _employeeDisplayName(e).toLowerCase();
      final phone = (e['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _mobileSlice {
    final list = _filteredEmployees;
    final start = (mobilePage - 1) * _employeesMobilePageSize;
    if (start >= list.length) return const [];
    final end = (start + _employeesMobilePageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  int get _activeCount => _filteredEmployees.where((e) => e['is_active'] == true).length;

  Map<int, String> get _outletNameById {
    final map = <int, String>{};
    for (final o in outlets) {
      final id = _asInt(o['id']);
      if (id != null) map[id] = (o['name'] ?? 'Магазин $id').toString();
    }
    return map;
  }

  int _sectionCount(Map<String, dynamic> record) {
    final sections = record['allowed_sections'];
    if (sections is List && sections.isNotEmpty) return sections.length;
    final perms = record['allowed_perms'];
    if (perms is Map<String, dynamic>) return countActivePermSections(perms);
    if (perms is Map) return countActivePermSections(perms.map((k, v) => MapEntry(k.toString(), v)));
    return 0;
  }

  String _storeLabel(Map<String, dynamic> record) {
    final ids = (record['store_ids'] is List) ? (record['store_ids'] as List).map(_asInt).whereType<int>().toList() : <int>[];
    if (ids.isEmpty) return 'Все магазины';
    final names = ids.map((id) => _outletNameById[id]).whereType<String>().where((s) => s.isNotEmpty).toList();
    if (names.isNotEmpty) return names.length == 1 ? names.first : '${names.length} магазина';
    return '${ids.length} магаз.';
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

  Future<void> _loadOutlets() async {
    final wid = _asInt(_user?['warehouse']);
    if (wid == null) {
      if (mounted) setState(() => outlets = const []);
      return;
    }
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('inventory/outlets?warehouse=$wid');
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

  Future<void> _loadEmployees() async {
    if (_user == null) {
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
        setState(() => employees = const []);
        return;
      }
      if (res.statusCode != 200) {
        setState(() => employees = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      setState(() {
        employees = list;
        mobilePage = 1;
      });
    } catch (_) {
      if (mounted) setState(() => employees = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать доступ?'),
        content: Text('${_employeeDisplayName(record)} (${_formatPhone(record['phone'])}) больше не будет иметь доступа к складу.'),
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
      if (res.statusCode != 200) throw Exception(_firstApiError(_tryJsonMap(res.body)));
      _snack('Доступ отозван');
      await _loadEmployees();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => revokingId = null);
    }
  }

  Widget _statusChip(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? _activeGreen.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? _activeGreen.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        active ? 'Активен' : 'Неактивен',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? const Color(0xFFB7EB8F) : Colors.white.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  Widget _mobileCard(Map<String, dynamic> r, {required bool canManage}) {
    final id = _asInt(r['id']);
    final isActive = r['is_active'] == true;
    const compact = BoxConstraints.tightFor(width: 34, height: 34);

    return Material(
      color: _cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: id == null ? null : () => Navigator.of(context).pushNamed('/employees/$id'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _employeeDisplayName(r),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  _statusChip(isActive),
                ],
              ),
              const SizedBox(height: 6),
              Text(_formatPhone(r['phone']), style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metaItem(Icons.storefront_outlined, _storeLabel(r)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _metaItem(Icons.groups_outlined, '${_sectionCount(r)} разделов'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    _formatJoinedDate(r['date_joined']),
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                  ),
                  const Spacer(),
                  if (canManage && id != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                          tooltip: 'Просмотр',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: compact,
                          color: Colors.white.withValues(alpha: 0.85),
                          onPressed: () => Navigator.of(context).pushNamed('/employees/$id'),
                        ),
                        if (_canAddRevoke) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Изменить',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: compact,
                            color: Colors.white.withValues(alpha: 0.85),
                            onPressed: () => Navigator.of(context).pushNamed('/employees/$id/edit'),
                          ),
                          IconButton(
                            icon: revokingId == id
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.person_remove_alt_1_outlined, size: 18, color: Color(0xFFF87171)),
                            tooltip: 'Отозвать доступ',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: compact,
                            onPressed: revokingId == id ? null : () => _revoke(r),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredEmployees;
    final totalPages = filtered.isEmpty ? 1 : (filtered.length / _employeesMobilePageSize).ceil();
    final canManage = _canAddRevoke || _isPlatform;

    if (u == null || !canAccessSection(u, 'employees', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await _loadWarehousesIfNeeded();
                await _loadOutlets();
                await _loadEmployees();
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(12, 8, 12, _canAddRevoke ? 88 : 12),
                children: [
                  Text('Сотрудники', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  if (_isBusinessman && u['warehouse'] != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront_rounded, size: 16, color: const Color(0xFF60A5FA)),
                          const SizedBox(width: 6),
                          Text(
                            (u['warehouse_name'] ?? 'Склад').toString(),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _contextBlue),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('$_activeCount', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                      Text(' активных', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      Text(' · ', style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.4))),
                      Text('${filtered.length}', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                      Text(' всего', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                  if (_isPlatform) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: warehouseFilter,
                            decoration: const InputDecoration(
                              labelText: 'Склад',
                              border: OutlineInputBorder(),
                              isDense: true,
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
                              setState(() {
                                warehouseFilter = v;
                                mobilePage = 1;
                              });
                              _loadEmployees();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pushNamed('/moderators'),
                          child: const Text('Модераторы'),
                        ),
                      ],
                    ),
                  ],
                  if (_canAddRevoke) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Поиск по имени или телефону',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                      ),
                      onChanged: (v) => setState(() {
                        search = v;
                        mobilePage = 1;
                      }),
                    ),
                  ],
                  if (_isBusinessman && u['warehouse'] == null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        'Укажите склад в профиле, чтобы добавлять сотрудников.',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (loading && filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (loading)
                    const SkeletonListBlock(rows: 4)
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _canAddRevoke ? 'Нет сотрудников. Нажмите «Добавить».' : 'Нет данных.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                      ),
                    )
                  else ...[
                    for (var i = 0; i < _mobileSlice.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _mobileCard(_mobileSlice[i], canManage: canManage),
                    ],
                    if (filtered.length > _employeesMobilePageSize) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: mobilePage > 1 ? () => setState(() => mobilePage--) : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text('$mobilePage / $totalPages', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                          IconButton(
                            onPressed: mobilePage < totalPages ? () => setState(() => mobilePage++) : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (_canAddRevoke)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/employees/add'),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Добавить сотрудника'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
