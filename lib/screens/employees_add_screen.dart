import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../widgets/app_scaffold.dart';
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

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Локальная часть TJ: 9 цифр без префикса 992 (как на сервере canonical_phone).
String _employeePhone9Local(String raw) {
  var d = _digits(raw);
  if (d.startsWith('992')) {
    d = d.length >= 12 ? d.substring(3, 12) : d.substring(3);
  }
  if (d.length > 9) d = d.substring(0, 9);
  return d;
}

bool _isValidEmployeeLocal9(String d) => d.length == 9 && RegExp(r'^[1-9]\d{8}$').hasMatch(d);

class EmployeesAddScreen extends StatefulWidget {
  const EmployeesAddScreen({super.key});

  @override
  State<EmployeesAddScreen> createState() => _EmployeesAddScreenState();
}

class _EmployeesAddScreenState extends State<EmployeesAddScreen> {
  final phoneCtrl = TextEditingController();
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();

  List<Map<String, dynamic>> outlets = const [];
  final Set<int> storeIds = <int>{};

  Map<String, dynamic> perms = const {};

  bool loading = false;
  bool codeSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOutlets());
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    codeCtrl.dispose();
    super.dispose();
  }

  bool get _canAdd {
    final u = context.read<SessionController>().user;
    return (u?['role'] as String?) == 'businessman' && u?['warehouse'] != null;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _loadOutlets() async {
    final u = context.read<SessionController>().user;
    final wid = _asInt(u?['warehouse']);
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

  bool _validateBase() {
    final phone = _employeePhone9Local(phoneCtrl.text);
    if (!_isValidEmployeeLocal9(phone)) {
      _snack('Введите 9 цифр местного номера после +992 (без ведущего нуля)', error: true);
      return false;
    }
    if (firstNameCtrl.text.trim().isEmpty) {
      _snack('Введите имя', error: true);
      return false;
    }
    if (lastNameCtrl.text.trim().isEmpty) {
      _snack('Введите фамилию', error: true);
      return false;
    }
    return true;
  }

  Future<void> _sendCode() async {
    if (!_canAdd) return;
    if (!_validateBase()) return;
    setState(() => loading = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'me/employees/send-code/',
        body: {
          'phone': _employeePhone9Local(phoneCtrl.text),
          'first_name': firstNameCtrl.text.trim(),
          'last_name': lastNameCtrl.text.trim(),
          'store_ids': storeIds.toList(),
          'allowed_perms': perms,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла. Войдите снова.', error: true);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      if (res.statusCode != 200) throw Exception(_firstApiError(data));
      setState(() => codeSent = true);
      final debug = data['debug_code'];
      _snack(debug != null ? 'Код: $debug' : 'Код отправлен');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _confirmAdd() async {
    if (!_canAdd) return;
    if (!_validateBase()) return;
    final code = _digits(codeCtrl.text);
    if (code.length != 6) {
      _snack('Введите 6 цифр кода', error: true);
      return;
    }
    setState(() => loading = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post(
        'me/employees/add/',
        body: {
          'phone': _employeePhone9Local(phoneCtrl.text),
          'first_name': firstNameCtrl.text.trim(),
          'last_name': lastNameCtrl.text.trim(),
          'code': code,
          'store_ids': storeIds.toList(),
          'allowed_perms': perms,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        _snack('Сессия истекла. Войдите снова.', error: true);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      if (res.statusCode != 200 && res.statusCode != 201) throw Exception(_firstApiError(data));
      _snack('Сотрудник зарегистрирован');
      Navigator.of(context).pop(); // back to list
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2438),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.65)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canAdd = _canAdd;

    if (!canAdd) {
      return AppScaffold(
        showBottomNav: false,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Добавить сотрудника', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text('Укажите склад в профиле.', style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('К списку')),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      showBottomNav: false,
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Назад'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: Colors.white.withValues(alpha: 0.75),
                    padding: EdgeInsets.zero,
                  ),
                ),
                Text('Новый сотрудник', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stepDot(1, codeSent ? false : true),
                    Expanded(child: Container(height: 2, color: codeSent ? const Color(0xFF2563EB) : Colors.white24)),
                    _stepDot(2, codeSent),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Данные', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    Text('SMS', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard('Контакты', Icons.person_outline, [
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Телефон сотрудника',
                        hintText: '901234567 или 784068008',
                        prefixText: '+992 ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      onChanged: (raw) {
                        var d = _employeePhone9Local(raw);
                        if (phoneCtrl.text != d) {
                          phoneCtrl.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                  TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Фамилия', border: OutlineInputBorder())),
                ]),
                _sectionCard('Магазины', Icons.storefront_outlined, [
                  Text(
                    'Выберите, к каким магазинам склада будет доступ у продавца.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 8),
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
                                shape: AppShape.roundedRect,
                              ),
                        ],
                      ),
                ]),
                _sectionCard('Права', Icons.security_outlined, [
                  EmployeePermsEditor(
                    value: perms,
                    onChanged: (next) => setState(() => perms = next),
                  ),
                ]),
                if (codeSent)
                  _sectionCard('SMS-подтверждение', Icons.sms_outlined, [
                    Text('Введите 6-значный код из SMS', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'Код', hintText: '000000', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 6),
                      onChanged: (v) {
                        final d = _digits(v);
                        if (d != v) {
                          codeCtrl.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                        }
                      },
                    ),
                  ]),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!codeSent)
                      FilledButton(
                        onPressed: loading ? null : _sendCode,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Отправить код'),
                      )
                    else ...[
                      FilledButton(
                        onPressed: loading ? null : _confirmAdd,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Сохранить'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: loading ? null : _sendCode,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                        child: const Text('Отправить код заново'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepDot(int n, bool active) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2563EB) : Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.white54)),
    );
  }
}

