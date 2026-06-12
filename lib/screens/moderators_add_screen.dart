import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';

const _blue = Color(0xFF2563EB);

class ModeratorsAddScreen extends StatefulWidget {
  const ModeratorsAddScreen({super.key});

  @override
  State<ModeratorsAddScreen> createState() => _ModeratorsAddScreenState();
}

class _ModeratorsAddScreenState extends State<ModeratorsAddScreen> {
  final phoneCtrl = TextEditingController();
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  bool loading = false;
  bool codeSent = false;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;
  bool get _canAdd => (_user?['role'] as String?) == 'businessman' && businessmanHasWarehouse(_user);

  @override
  void dispose() {
    phoneCtrl.dispose();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    codeCtrl.dispose();
    super.dispose();
  }

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _sendCode() async {
    final phone = _digits(phoneCtrl.text);
    final fn = firstNameCtrl.text.trim();
    final ln = lastNameCtrl.text.trim();
    if (phone.isEmpty || fn.isEmpty || ln.isEmpty) {
      _snack('Заполните телефон, имя и фамилию', error: true);
      return;
    }
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().post(
        'me/moderators/send-code/',
        body: {'phone': phone, 'first_name': fn, 'last_name': ln},
      );
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        return;
      }
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(data is Map ? data['detail']?.toString() ?? 'Ошибка' : 'Ошибка');
      }
      setState(() => codeSent = true);
      final debug = data is Map ? data['debug_code']?.toString() : null;
      _snack(debug != null ? 'Код: $debug' : 'Код отправлен');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _confirmAdd() async {
    final phone = _digits(phoneCtrl.text);
    final code = _digits(codeCtrl.text);
    if (phone.isEmpty || code.isEmpty) {
      _snack('Введите код из SMS', error: true);
      return;
    }
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().post(
        'me/moderators/add/',
        body: {
          'phone': phone,
          'first_name': firstNameCtrl.text.trim(),
          'last_name': lastNameCtrl.text.trim(),
          'code': code,
        },
      );
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (res.statusCode == 401) {
        await context.read<SessionController>().logout();
        return;
      }
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(data is Map ? data['detail']?.toString() ?? 'Ошибка' : 'Ошибка');
      }
      _snack('Модератор добавлен');
      Navigator.of(context).pushReplacementNamed('/moderators');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_canAdd) {
      return AppScaffold(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Пригласить модератора', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text('Укажите склад в профиле. Только бизнесмен может приглашать модераторов.', style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Назад')),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          children: [
            Text('Пригласить модератора', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Модератор войдёт по SMS и увидит вашу реферальную статистику (как у вас в разделе «Реферал»).',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Телефон *', hintText: '992XXXXXXXX', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'Имя *', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Фамилия *', border: OutlineInputBorder())),
            if (codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Код из SMS *', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: loading ? null : (codeSent ? _confirmAdd : _sendCode),
              style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size(double.infinity, 44)),
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(codeSent ? 'Подтвердить' : 'Отправить код'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ],
        ),
      ),
    );
  }
}
