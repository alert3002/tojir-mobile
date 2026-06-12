import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';
import 'employee_perms.dart';

const _cardBg = Color(0xFF1A2438);
const _blue = Color(0xFF2563EB);
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

String _employeeDisplayName(Map<String, dynamic>? emp) {
  if (emp == null) return 'Без имени';
  final fn = (emp['first_name'] ?? '').toString().trim();
  final ln = (emp['last_name'] ?? '').toString().trim();
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

String _formatJoined(dynamic v) {
  if (v == null) return '—';
  final d = DateTime.tryParse(v.toString());
  if (d == null) return v.toString().replaceFirst('T', ' ');
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}, $hh:$min';
}

bool _sectionIsAllowed(Map<String, dynamic> perms, String key) {
  final v = perms[key];
  if (v is! Map) return false;
  return v['view'] == true || v['create'] == true || v['edit'] == true || v['delete'] == true;
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
  bool revoking = false;

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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
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
      setState(() {
        employee = _tryJsonMap(res.body);
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

  List<({int id, String name})> _storeChips(Map<String, dynamic> emp) {
    final ids = (emp['store_ids'] is List) ? (emp['store_ids'] as List).map(_asInt).whereType<int>().toList() : <int>[];
    if (ids.isEmpty) return [(id: 0, name: 'Все магазины')];
    return ids.map((sid) {
      final name = outlets.firstWhere((o) => _asInt(o['id']) == sid, orElse: () => const {})['name']?.toString();
      return (id: sid, name: (name != null && name.trim().isNotEmpty) ? name : 'Магазин #$sid');
    }).toList();
  }

  Future<void> _revoke() async {
    final emp = employee;
    if (emp == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать доступ?'),
        content: Text('${_employeeDisplayName(emp)} больше не сможет работать в вашем складе.'),
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

    setState(() => revoking = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.patch('me/employees/${widget.id}/revoke/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        final data = _tryJsonMap(res.body);
        throw Exception(data['detail']?.toString() ?? 'Ошибка');
      }
      _snack('Доступ отозван');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => revoking = false);
    }
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.65)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final emp = employee;

    if (u == null || !canAccessSection(u, 'employees', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    return AppScaffold(
      showBottomNav: false,
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            if (loading)
              const SingleChildScrollView(child: SkeletonListBlock(rows: 8))
            else if (emp == null)
              Center(
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
              )
            else
              ListView(
                padding: EdgeInsets.fromLTRB(12, 8, 12, _canEdit ? 100 : 12),
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('К списку'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: Colors.white.withValues(alpha: 0.75),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _employeeDisplayName(emp).substring(0, 1).toUpperCase(),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _employeeDisplayName(emp),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.phone_outlined, size: 14, color: Colors.white.withValues(alpha: 0.55)),
                                      const SizedBox(width: 6),
                                      Text(_formatPhone(emp['phone']), style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _pill('Продавец', _blue),
                                      _pill(
                                        emp['is_active'] == true ? 'Активен' : 'Неактивен',
                                        emp['is_active'] == true ? _activeGreen : Colors.white54,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Добавлен: ${_formatJoined(emp['date_joined'])}',
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    title: 'Магазины',
                    icon: Icons.storefront_outlined,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in _storeChips(emp))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Text(s.name, style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    title: 'Права доступа',
                    icon: Icons.security_outlined,
                    child: Builder(
                      builder: (context) {
                        final perms = (emp['allowed_perms'] is Map)
                            ? Map<String, dynamic>.from(emp['allowed_perms'] as Map)
                            : <String, dynamic>{};
                        final active = sellerSections.where((s) => _sectionIsAllowed(perms, s.key)).toList();
                        if (active.isEmpty) {
                          return Text('Права не назначены', style: TextStyle(color: cs.onSurfaceVariant));
                        }
                        return Column(
                          children: [
                            for (var i = 0; i < active.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _permRow(active[i], perms[active[i].key]),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            if (_canEdit && !loading && emp != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed('/employees/${widget.id}/edit'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Изменить'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _blue,
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: revoking ? null : _revoke,
                        icon: revoking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.person_remove_alt_1_outlined, size: 18),
                        label: const Text('Отозвать доступ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
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

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.95))),
    );
  }

  Widget _permRow(SellerSection sec, dynamic rawActions) {
    final actions = rawActions is Map ? rawActions : const {};
    final labels = permActions.where((a) => actions[a.key] == true).map((a) => a.value).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(sec.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final l in labels)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(l, style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ],
    );
  }
}
