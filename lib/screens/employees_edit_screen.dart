import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
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

String _firstApiError(Map<String, dynamic> m, {String fallback = 'Ошибка'}) {
  final d = m['detail'];
  if (d is String && d.isNotEmpty) return d;
  return fallback;
}

class EmployeesEditScreen extends StatefulWidget {
  const EmployeesEditScreen({super.key, required this.id});

  final int id;

  @override
  State<EmployeesEditScreen> createState() => _EmployeesEditScreenState();
}

class _EmployeesEditScreenState extends State<EmployeesEditScreen> {
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController lastNameCtrl = TextEditingController();

  List<Map<String, dynamic>> outlets = const [];
  final Set<int> storeIds = <int>{};
  Map<String, dynamic> perms = const {};

  bool fetchLoading = true;
  bool saving = false;

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

  @override
  void dispose() {
    phoneCtrl.dispose();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _loadEmployee() async {
    setState(() => fetchLoading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('me/employees/${widget.id}/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        _snack('Сотрудник не найден', error: true);
        Navigator.of(context).pop();
        return;
      }
      final emp = _tryJsonMap(res.body);
      phoneCtrl.text = (emp['phone'] ?? '').toString();
      firstNameCtrl.text = (emp['first_name'] ?? '').toString();
      lastNameCtrl.text = (emp['last_name'] ?? '').toString();
      final ids = (emp['store_ids'] is List) ? (emp['store_ids'] as List).map(_asInt).whereType<int>() : const <int>[];
      storeIds
        ..clear()
        ..addAll(ids);
      perms = (emp['allowed_perms'] is Map) ? Map<String, dynamic>.from(emp['allowed_perms'] as Map) : <String, dynamic>{};
      setState(() => fetchLoading = false);
    } catch (_) {
      if (mounted) {
        _snack('Сотрудник не найден', error: true);
        Navigator.of(context).pop();
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

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => saving = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch(
        'me/employees/${widget.id}/',
        body: {
          'first_name': firstNameCtrl.text.trim(),
          'last_name': lastNameCtrl.text.trim(),
          'store_ids': storeIds.toList(),
          'allowed_perms': perms,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200) throw Exception(_firstApiError(data));
      _snack('Сохранено');
      Navigator.of(context).pop();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_canEdit) {
      return const AppScaffold(
        showBottomNav: false,
        child: SafeArea(top: false, child: Center(child: Text('Редактирование только у бизнесмена.'))),
      );
    }

    return AppScaffold(
      showBottomNav: false,
      child: SafeArea(
        top: false,
        child: fetchLoading
            ? const SingleChildScrollView(child: SkeletonListBlock(rows: 8))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Text('Изменить сотрудника',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    'Изменение имени, фамилии, доступа в магазины и прав по действиям. Телефон не редактируется.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: phoneCtrl,
                            decoration: const InputDecoration(labelText: 'Телефон', border: OutlineInputBorder()),
                            enabled: false,
                          ),
                          const SizedBox(height: 12),
                          TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Фамилия', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          Text('Доступ в магазины', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                          const SizedBox(height: 6),
                          if (outlets.isEmpty)
                            Text('Магазины не найдены', style: TextStyle(color: cs.onSurfaceVariant))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final o in outlets)
                                  if (_asInt(o['id']) != null)
                                    FilterChip(
                                      label: Text((o['name'] ?? 'Магазин ${o['id']}').toString()),
                                      selected: storeIds.contains(_asInt(o['id'])!),
                                      onSelected: (v) {
                                        final id = _asInt(o['id'])!;
                                        setState(() {
                                          if (v) {
                                            storeIds.add(id);
                                          } else {
                                            storeIds.remove(id);
                                          }
                                        });
                                      },
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          EmployeePermsEditor(
                            value: perms,
                            onChanged: (next) => setState(() => perms = next),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton(onPressed: saving ? null : _save, child: const Text('Сохранить')),
                              TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(), child: const Text('Отмена')),
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pushNamed('/employees/${widget.id}'),
                                child: const Text('Просмотр'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

