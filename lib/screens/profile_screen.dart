import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../utils/platform_info.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

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

String _formatBalanceStatus(String entryType, String? status) {
  if (entryType == 'withdraw') {
    if (status == 'pending') return 'На рассмотрении';
    if (status == 'approved') return 'Выполнено';
    if (status == 'rejected') return 'Отклонено';
    return status ?? '—';
  }
  if (status == 'charged') return 'Оплачено';
  if (status == 'pending') return 'Ожидает оплаты';
  if (status == 'void') return 'Аннулировано';
  if (status == 'failed') return 'Ошибка';
  return status ?? '—';
}

String _fmtDt(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString();
  try {
    final dt = DateTime.parse(s).toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yy $hh:$mi';
  } catch (_) {
    return s.replaceFirst('T', ' ');
  }
}

String _fmtDate(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString();
  try {
    final dt = DateTime.parse(s).toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    return '$dd.$mm.$yy';
  } catch (_) {
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.focusWarehouse = false});

  /// После открытия сразу прокрутить к полям склада (название / адрес).
  final bool focusWarehouse;

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  bool editing = false;
  bool savingProfile = false;

  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController lastNameCtrl = TextEditingController();

  bool topupLoading = false;
  String topupProvider = 'alif';
  final TextEditingController topupAmountCtrl = TextEditingController(text: '10');

  bool withdrawLoading = false;
  final TextEditingController withdrawAmountCtrl = TextEditingController(text: '10');
  final TextEditingController withdrawNoteCtrl = TextEditingController();

  bool historyLoading = false;
  List<Map<String, dynamic>> balanceHistory = const [];

  bool clientDebtsLoading = false;
  List<Map<String, dynamic>> clientDebts = const [];

  bool editingWarehouse = false;
  bool warehouseSaving = false;
  bool warehouseDeleting = false;
  bool accountDeleting = false;
  final TextEditingController warehouseNameCtrl = TextEditingController();
  final TextEditingController warehouseAddressCtrl = TextEditingController();
  final GlobalKey _warehouseSectionKey = GlobalKey();
  final FocusNode _warehouseNameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.focusWarehouse) {
      editingWarehouse = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Не вызываем bootstrap() — он ставит isReady=false и снова показывает загрузку.
      _syncFromUser();
      await _loadBalanceHistory();
      await _loadClientDebtsIfNeeded();
      if (widget.focusWarehouse) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (mounted) focusWarehouseFields();
      }
    });
  }

  /// Прокрутка к блоку «Склад» и фокус на название.
  void focusWarehouseFields() {
    if (!mounted) return;
    setState(() => editingWarehouse = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _warehouseSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
      _warehouseNameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    topupAmountCtrl.dispose();
    withdrawAmountCtrl.dispose();
    withdrawNoteCtrl.dispose();
    warehouseNameCtrl.dispose();
    warehouseAddressCtrl.dispose();
    _warehouseNameFocus.dispose();
    super.dispose();
  }

  String _cleanMsg(Object msg) {
    return msg.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final text = _cleanMsg(msg);
    if (text.isEmpty) return;
    if (error) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ошибка'),
          content: Text(text),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ОК'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  void _syncFromUser() {
    final u = _user;
    if (u == null) return;
    firstNameCtrl.text = (u['first_name'] ?? '').toString();
    lastNameCtrl.text = (u['last_name'] ?? '').toString();
    warehouseNameCtrl.text = (u['warehouse_name'] ?? '').toString();
    warehouseAddressCtrl.text = (u['warehouse_address'] ?? '').toString();
  }

  Future<void> _saveProfile() async {
    final api = context.read<ApiClient>();
    setState(() => savingProfile = true);
    try {
      final res = await api.patch('me/', body: {'first_name': firstNameCtrl.text.trim(), 'last_name': lastNameCtrl.text.trim()});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('Не удалось сохранить профиль');
      await context.read<SessionController>().reloadUser();
      if (!mounted) return;
      _syncFromUser();
      _snack('Профиль обновлён');
      setState(() => editing = false);
    } catch (_) {
      _snack('Не удалось сохранить профиль', error: true);
    } finally {
      if (mounted) setState(() => savingProfile = false);
    }
  }

  Future<void> _loadBalanceHistory() async {
    setState(() => historyLoading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('me/balance/history/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => balanceHistory = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      setState(() => balanceHistory = list);
    } catch (_) {
      if (mounted) setState(() => balanceHistory = const []);
    } finally {
      if (mounted) setState(() => historyLoading = false);
    }
  }

  Future<void> _loadClientDebtsIfNeeded() async {
    final u = _user;
    if (u == null || (u['role'] as String?) != 'client') {
      setState(() => clientDebts = const []);
      return;
    }
    setState(() => clientDebtsLoading = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.get('me/debts/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => clientDebts = const []);
        return;
      }
      final j = jsonDecode(res.body);
      setState(() => clientDebts = j is List ? j.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
    } catch (_) {
      if (mounted) setState(() => clientDebts = const []);
    } finally {
      if (mounted) setState(() => clientDebtsLoading = false);
    }
  }

  Future<void> _topup({VoidCallback? closeDialog}) async {
    final amount = double.tryParse(topupAmountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount < 2) {
      _snack('Минимальная сумма — 2 сомони', error: true);
      return;
    }
    if (isIosApp) {
      _snack('Оплатите через банк и отправьте чек в Telegram или WhatsApp');
      return;
    }
    if (topupProvider != 'alif' && topupProvider != 'smartpay') {
      _snack('Выберите способ оплаты', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    try {
      final res = await api.post(
        'me/balance/topup/',
        body: {
          'amount': amount,
          'return_url': 'https://api.tojir.tj/payment/return/app/',
          'provider': topupProvider,
        },
      );
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception((data['detail'] ?? 'Ошибка создания платежа').toString());
      }
      final link = (data['payment_link'] ?? '').toString();
      if (link.isEmpty) throw Exception('Нет ссылки на оплату');
      final uri = Uri.tryParse(link);
      if (uri == null) throw Exception('Некорректная ссылка оплаты');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('Не удалось открыть ссылку оплаты');
      closeDialog?.call();
      _snack(
        topupProvider == 'smartpay'
            ? 'Откройте оплату SmartPay в браузере и вернитесь в приложение'
            : 'Откройте оплату Alif в браузере и вернитесь в приложение',
      );
    } catch (e) {
      _snack(_cleanMsg(e), error: true);
    }
  }

  Future<void> _withdraw({VoidCallback? closeDialog}) async {
    final amount = double.tryParse(withdrawAmountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount < 1) {
      _snack('Минимальная сумма вывода — 1 сомони', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    try {
      final res = await api.post('me/balance/withdraw/', body: {'amount': amount, 'note': withdrawNoteCtrl.text.trim()});
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) throw Exception((data['detail'] ?? 'Ошибка заявки').toString());
      _snack((data['detail'] ?? 'Заявка отправлена').toString());
      closeDialog?.call();
      withdrawNoteCtrl.clear();
      await _loadBalanceHistory();
    } catch (e) {
      _snack(_cleanMsg(e), error: true);
    }
  }

  Future<void> _saveWarehouse() async {
    final name = warehouseNameCtrl.text.trim();
    final address = warehouseAddressCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Введите название склада', error: true);
      return;
    }
    if (address.isEmpty) {
      _snack('Введите адрес склада', error: true);
      return;
    }
    setState(() => warehouseSaving = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.patch('me/', body: {'warehouse_name': name, 'warehouse_address': address});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('Ошибка');
      await context.read<SessionController>().reloadUser();
      if (!mounted) return;
      _syncFromUser();
      _snack('Склад сохранён');
      setState(() => editingWarehouse = false);
    } catch (_) {
      _snack('Не удалось сохранить склад', error: true);
    } finally {
      if (mounted) setState(() => warehouseSaving = false);
    }
  }

  Future<void> _deleteWarehouse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить склад?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => warehouseDeleting = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.patch('me/', body: {'warehouse_name': '', 'warehouse_address': ''});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('Ошибка');
      if (!context.mounted) return;
      await context.read<SessionController>().reloadUser();
      if (!mounted) return;
      _syncFromUser();
      _snack('Склад удалён');
    } catch (_) {
      _snack('Не удалось удалить склад', error: true);
    } finally {
      if (mounted) setState(() => warehouseDeleting = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Действие необратимо. Вы выйдете из системы, а доступ к аккаунту будет отключён.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить аккаунт'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => accountDeleting = true);
    try {
      final res = await context.read<ApiClient>().delete('me/');
      if (!mounted) return;
      final data = _tryJsonMap(res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(data['detail']?.toString() ?? 'Не удалось удалить аккаунт');
      }
      _snack((data['detail'] ?? 'Аккаунт удалён').toString());
      if (!context.mounted) return;
      await context.read<SessionController>().logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => accountDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    if (u == null || !canAccessSection(u, 'profile', null)) {
      // profile is generally available, but keep gate consistent
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final role = (u['role'] as String?) ?? '';
    final fullName = [u['first_name'], u['last_name']].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    final balance = _asDouble(u['balance']) ?? 0;

    final hasWarehouse = role == 'businessman'
        ? businessmanHasWarehouse(u)
        : (u['warehouse_name'] ?? '').toString().trim().isNotEmpty;
    final showWarehouseForm = !hasWarehouse || editingWarehouse;

    final referralCode = (u['referral_code'] ?? '').toString();
    final referralCount = _asInt(u['referral_count']) ?? 0;
    final referralLink = referralCode.isEmpty ? '' : 'https://tojir.tj/login?ref=$referralCode';

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await context.read<SessionController>().reloadUser();
            if (!context.mounted) return;
            _syncFromUser();
            await _loadBalanceHistory();
            await _loadClientDebtsIfNeeded();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Text('Профиль', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Данные профиля', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (!editing) ...[
                        if (fullName.isNotEmpty) _kv('Имя', fullName, cs),
                        _kv('Телефон', (u['phone'] ?? '—').toString(), cs),
                        if (role.isNotEmpty) _kv('Роль', _roleLabel(role), cs),
                        if (role == 'seller') ...[
                          _kv('Склад', _sellerWarehouseLabel(u), cs),
                          _kv('Доступ в магазины', _allowedOutletNames(u), cs),
                        ],
                        if (!isIosApp)
                          _kv('Баланс', '${balance.toStringAsFixed(2)} TJS', cs, strong: true)
                        else if (balance > 0)
                          _kv('Реферальный баланс', '${balance.toStringAsFixed(2)} TJS', cs, strong: true),
                        const SizedBox(height: 10),
                        if (isIosApp) ...[
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).pushNamed('/tariffs'),
                            icon: const Icon(Icons.apple, size: 18),
                            label: const Text('Подписка через App Store'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Подписка TOJIr на iPhone/iPad оформляется только через App Store. '
                            'Баланс используется для реферальных начислений и вывода, не для оплаты подписки.',
                            style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
                          ),
                          if (balance > 0) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _openWithdrawDialog(balance),
                              icon: const Icon(Icons.remove, size: 18),
                              label: const Text('Запросить вывод'),
                            ),
                          ],
                        ] else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: isIosApp
                                    ? null
                                    : () {
                                        topupProvider = 'alif';
                                        _openTopupDialog(balance);
                                      },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Пополнить баланс'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  shape: AppShape.roundedRect,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openWithdrawDialog(balance),
                                icon: const Icon(Icons.remove, size: 18),
                                label: const Text('Запросить вывод'),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => setState(() => editing = true),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Редактировать'),
                        ),
                      ] else ...[
                        TextField(controller: firstNameCtrl, decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Фамилия', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton(
                              onPressed: savingProfile ? null : _saveProfile,
                              child: savingProfile
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Сохранить'),
                            ),
                            TextButton(onPressed: savingProfile ? null : () => setState(() => editing = false), child: const Text('Отменить')),
                          ],
                        ),
                      ],
                      if (role == 'businessman') ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 10),
                        KeyedSubtree(
                          key: _warehouseSectionKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Склад', style: TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              if (showWarehouseForm) ...[
                                TextField(
                                  controller: warehouseNameCtrl,
                                  focusNode: _warehouseNameFocus,
                                  decoration: const InputDecoration(
                                    labelText: 'Название склада *',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: warehouseAddressCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Адрес *',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: warehouseSaving ? null : _saveWarehouse,
                                  child: warehouseSaving
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Сохранить'),
                                ),
                              ] else ...[
                                _kv('Название склада', (u['warehouse_name'] ?? '—').toString(), cs),
                                _kv('Адрес', (u['warehouse_address'] ?? '—').toString(), cs),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () => setState(() => editingWarehouse = true),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Изменить'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: warehouseDeleting ? null : _deleteWarehouse,
                                      style: FilledButton.styleFrom(backgroundColor: cs.error),
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      label: warehouseDeleting
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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
                      const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).pushNamed('/offline-queue'),
                        icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                        label: const Text('Офлайн-очередь'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed('/support'),
                        icon: const Icon(Icons.support_agent_outlined, size: 18),
                        label: const Text('Поддержка'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed('/privacy'),
                        icon: const Icon(Icons.policy_outlined, size: 18),
                        label: const Text('Политика конфиденциальности'),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'Удаление аккаунта отключает доступ и отвязывает номер телефона. Действие необратимо.',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: accountDeleting ? null : _deleteAccount,
                        style: FilledButton.styleFrom(backgroundColor: cs.error),
                        icon: accountDeleting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.delete_forever_outlined, size: 18),
                        label: const Text('Удалить аккаунт'),
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
                      const Text('История баланса', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (historyLoading) const SkeletonListBlock(rows: 6)
else if (balanceHistory.isEmpty)
                        Text('Нет операций', style: TextStyle(color: cs.onSurfaceVariant))
                      else
                        ...balanceHistory.map((r) {
                          final type = (r['entry_type'] ?? '').toString();
                          final status = (r['status'] ?? '').toString();
                          final rawAt = r['occurred_at'] ?? r['created_at'];
                          final amount = _asDouble(r['amount']);
                          final cur = (r['currency'] ?? 'TJS').toString();
                          final sign = type == 'withdraw' ? '−' : '+';
                          final color = type == 'withdraw' ? cs.error : cs.primary;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: AppShape.br,
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(type == 'withdraw' ? 'Вывод' : 'Пополнение', style: const TextStyle(fontWeight: FontWeight.w800))),
                                    Text(
                                      amount != null ? '$sign${amount.toStringAsFixed(2)} $cur' : '—',
                                      style: TextStyle(fontWeight: FontWeight.w900, color: color),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(_fmtDt(rawAt), style: TextStyle(color: cs.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text('Статус: ${_formatBalanceStatus(type, status)}', style: TextStyle(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              if (role == 'client') ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Мои долги', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                          'Задолженность перед магазином / складом (насия), оформленная на ваш номер телефона в профиле.',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        if (clientDebtsLoading) const SkeletonListBlock(rows: 5)
else if (clientDebts.isEmpty)
                          Text('Нет открытых долгов по этому номеру', style: TextStyle(color: cs.onSurfaceVariant))
                        else
                          ...clientDebts.map((d) {
                            final creditor = (d['creditor_label'] ?? '—').toString();
                            final rem = _asDouble(d['amount_remaining']) ?? 0;
                            final tot = _asDouble(d['amount_total']) ?? 0;
                            final paid = _asDouble(d['amount_paid']) ?? 0;
                            final cur = (d['currency'] ?? 'TJS').toString();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: AppShape.br,
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(creditor, style: const TextStyle(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text('Остаток: ${rem.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text('Всего / оплачено: ${tot.toStringAsFixed(2)} / ${paid.toStringAsFixed(2)} $cur',
                                      style: TextStyle(color: cs.onSurfaceVariant)),
                                  Text('Дата: ${_fmtDate(d['created_at'])}', style: TextStyle(color: cs.onSurfaceVariant)),
                                  Text('Срок: ${_fmtDate(d['due_date'])}', style: TextStyle(color: cs.onSurfaceVariant)),
                                  Text('Примечание: ${(d['note'] ?? '—').toString()}', style: TextStyle(color: cs.onSurfaceVariant)),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
              if (role != 'seller') ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('Реферальная программа', style: TextStyle(fontWeight: FontWeight.w800))),
                            TextButton(onPressed: () => Navigator.of(context).pushNamed('/referral'), child: const Text('Подробнее →')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Реферальный код: ${referralCode.isEmpty ? '—' : referralCode}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Приглашённых: $referralCount', style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Text('Начисления с реферальной программы будут зачисляться на баланс.',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 10),
                        if (referralLink.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: Text(referralLink, style: TextStyle(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: referralLink));
                                  _snack('Ссылка скопирована');
                                },
                                icon: const Icon(Icons.copy),
                                tooltip: 'Копировать',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTopupDialog(double balance) async {
    if (!mounted || isIosApp) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !topupLoading,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Пополнить баланс'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Укажите сумму и выберите платёжную систему. Оплата откроется по документации провайдера.',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: topupAmountCtrl,
                        decoration: const InputDecoration(labelText: 'Сумма (TJS)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      ),
                      const SizedBox(height: 12),
                      Text('Способ оплаты', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _PayProviderTile(
                              selected: topupProvider == 'alif',
                              label: 'Alif',
                              hint: 'Карты, Alif Mobi',
                              onTap: () => setLocal(() => topupProvider = 'alif'),
                              child: Image.asset('assets/payments/alif.png', fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PayProviderTile(
                              selected: topupProvider == 'smartpay',
                              label: 'SmartPay',
                              hint: 'Карты и кошельки',
                              onTap: () => setLocal(() => topupProvider = 'smartpay'),
                              child: SvgPicture.asset('assets/payments/smartpay.svg', fit: BoxFit.contain),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Текущий баланс: ${balance.toStringAsFixed(2)} TJS',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: topupLoading ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: topupLoading
                      ? null
                      : () async {
                          setLocal(() => topupLoading = true);
                          setState(() => topupLoading = true);
                          try {
                            await _topup(closeDialog: () {
                              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                            });
                          } finally {
                            if (mounted) setState(() => topupLoading = false);
                            if (dialogCtx.mounted) setLocal(() => topupLoading = false);
                          }
                        },
                  child: topupLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(topupProvider == 'smartpay' ? 'Оплатить через SmartPay' : 'Оплатить через Alif'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openWithdrawDialog(double balance) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !withdrawLoading,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Запрос на вывод средств'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Заявка уйдёт администратору. С баланса сумма спишется только после одобрения.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: withdrawAmountCtrl,
                        decoration: InputDecoration(
                          labelText: 'Сумма (TJS)',
                          helperText: 'Макс: ${balance.toStringAsFixed(2)}',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: withdrawNoteCtrl,
                        decoration: const InputDecoration(labelText: 'Комментарий (необязательно)', border: OutlineInputBorder()),
                        maxLength: 2000,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: withdrawLoading ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: withdrawLoading
                      ? null
                      : () async {
                          setLocal(() => withdrawLoading = true);
                          setState(() => withdrawLoading = true);
                          try {
                            await _withdraw(closeDialog: () {
                              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                            });
                          } finally {
                            if (mounted) setState(() => withdrawLoading = false);
                            if (dialogCtx.mounted) setLocal(() => withdrawLoading = false);
                          }
                        },
                  child: withdrawLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Отправить заявку'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _kv(String k, String v, ColorScheme cs, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700)),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'platform' => 'Платформа (админ)',
      'moderator' => 'Модератор',
      'businessman' => 'Бизнесмен',
      'seller' => 'Продавец',
      'nasiya' => 'Насия',
      'client' => 'Клиент',
      _ => role,
    };
  }

  String _sellerWarehouseLabel(Map<String, dynamic> u) {
    final name = (u['warehouse_name'] ?? '').toString();
    final addr = (u['warehouse_address'] ?? '').toString();
    if (name.isEmpty) return '—';
    if (addr.isEmpty) return name;
    return '$name, $addr';
  }

  String _allowedOutletNames(Map<String, dynamic> u) {
    final v = u['allowed_outlet_names'];
    if (v is List && v.isNotEmpty) {
      final names = v.map((x) => x.toString()).where((s) => s.trim().isNotEmpty).toList();
      return names.isEmpty ? '—' : names.join(', ');
    }
    return '—';
  }
}

class _PayProviderTile extends StatelessWidget {
  const _PayProviderTile({
    required this.selected,
    required this.label,
    required this.hint,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? const Color(0xFF2563EB).withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF2563EB) : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                height: 44,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              ),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

