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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canAdd = _canAdd;

    if (!canAdd) {
      return const AppScaffold(
        showBottomNav: false,
        child: SafeArea(top: false, child: Center(child: Text('Укажите склад в профиле или доступ только у бизнесмена.'))),
      );
    }

    return AppScaffold(
      showBottomNav: false,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text('Добавить сотрудника', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Номер сотрудника — 9 цифр после +992 (код из SMS придёт на этот номер). Затем имя, фамилия, магазины и 6-значный код.',
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
                    const SizedBox(height: 12),
                    Text('Доступ в магазины', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 16),
                    EmployeePermsEditor(
                      value: perms,
                      onChanged: (next) => setState(() => perms = next),
                    ),
                    const SizedBox(height: 8),
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'SMS-код', hintText: '000000', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        onChanged: (v) {
                          final d = _digits(v);
                          if (d != v) {
                            codeCtrl.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: loading ? null : _sendCode,
                          child: Text(codeSent ? 'Отправить код заново' : 'Отправить код'),
                        ),
                        FilledButton(
                          onPressed: (!codeSent || loading) ? null : _confirmAdd,
                          child: const Text('Подтвердить'),
                        ),
                        TextButton(
                          onPressed: loading ? null : () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
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

