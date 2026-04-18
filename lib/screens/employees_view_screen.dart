import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import 'employee_perms.dart';

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

String _formatJoined(dynamic v) {
  if (v == null) return '—';
  final s = v.toString();
  return s.replaceFirst('T', ' ');
}

class EmployeesViewScreen extends StatefulWidget {
  const EmployeesViewScreen({super.key, required this.id});

  final int id;

  @override
  State<EmployeesViewScreen> createState() => _EmployeesViewScreenState();
}

class _EmployeesViewScreenState extends State<EmployeesViewScreen> {
  Map<String, dynamic>? employee;
  List<Map<String, dynamic>> outlets = const [];
  bool loading = true;

  bool get _canEdit {
    final u = context.read<SessionController>().user;
    return (u?['role'] as String?) == 'businessman' && u?['warehouse'] != null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadEmployee();
      await _loadOutlets();
    });
  }

  Future<void> _loadEmployee() async {
    setState(() => loading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('me/employees/${widget.id}/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          employee = null;
          loading = false;
        });
        return;
      }
      final j = _tryJsonMap(res.body);
      setState(() {
        employee = j;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          employee = null;
          loading = false;
        });
      }
    }
  }

  Future<void> _loadOutlets() async {
    final u = context.read<SessionController>().user;
    final wid = _asInt(u?['warehouse']);
    if (wid == null) return;
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

  String _storeNames(Map<String, dynamic> emp) {
    final ids = (emp['store_ids'] is List) ? (emp['store_ids'] as List).map(_asInt).whereType<int>().toList() : <int>[];
    if (ids.isEmpty) return '—';
    if (outlets.isEmpty) return 'ID: ${ids.join(', ')}';
    final names = ids
        .map((sid) => outlets.firstWhere((o) => _asInt(o['id']) == sid, orElse: () => const {})['name']?.toString())
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return names.isNotEmpty ? names.join(', ') : 'ID: ${ids.join(', ')}';
  }

  String _sectionLabels(Map<String, dynamic> emp) {
    final perms = emp['allowed_perms'];
    if (perms is! Map) return '—';
    final allowedKeys = <String>[];
    for (final sec in sellerSections) {
      final v = perms[sec.key];
      if (v is Map && (v['view'] == true || v['create'] == true || v['edit'] == true || v['delete'] == true)) {
        allowedKeys.add(sec.label);
      }
    }
    return allowedKeys.isEmpty ? '—' : allowedKeys.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'employees', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    return AppScaffold(
      showBottomNav: false,
      child: SafeArea(
        top: false,
        child: loading
            ? const SingleChildScrollView(child: SkeletonListBlock(rows: 8))
            : (employee == null)
                ? Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Сотрудник не найден.', style: TextStyle(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('К списку')),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Text('Просмотр сотрудника',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _kv('Телефон', (employee!['phone'] ?? '—').toString(), cs),
                              _kv('Имя', (employee!['first_name'] ?? '—').toString(), cs),
                              _kv('Фамилия', (employee!['last_name'] ?? '—').toString(), cs),
                              _kv('Роль', 'Продавец', cs),
                              _kv('Статус', employee!['is_active'] == true ? 'Активен' : 'Неактивен', cs),
                              _kv('Добавлен', _formatJoined(employee!['date_joined']), cs),
                              _kv('Доступ в магазины', _storeNames(employee!), cs),
                              _kv('Доступ к разделам', _sectionLabels(employee!), cs),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'В меню продавца отображаются только отмеченные разделы. Данные — только по складу бизнесмена.',
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('К списку')),
                          if (_canEdit)
                            FilledButton.tonal(
                              onPressed: () => Navigator.of(context).pushNamed('/employees/${widget.id}/edit'),
                              child: const Text('Изменить'),
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _kv(String k, String v, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

