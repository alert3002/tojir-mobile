import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';
import '../theme/app_shape.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

String _cleanBody(String? body) {
  final s = (body ?? '').trim();
  if (s.isEmpty) return '—';
  final lines = s.split(RegExp(r'\r?\n'));
  final filtered = lines.where((ln) {
    final t = ln.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('Остаток')) return false;
    return true;
  }).join('\n');
  return filtered.isEmpty ? '—' : filtered;
}

String _fmtDt(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $h:$mi';
  } catch (_) {
    return iso.replaceFirst('T', ' ');
  }
}

({String route, String label})? _linkForType(String? t) {
  switch (t) {
    case 'sale':
      return (route: '/sales', label: 'Продажи');
    case 'transfer':
      return (route: '/transfers', label: 'Перемещения');
    case 'rate':
      return (route: '/course', label: 'Курс');
    case 'stock':
      return (route: '/stores', label: 'Магазины');
    case 'debt':
      return (route: '/debts', label: 'Долги');
    default:
      return null;
  }
}

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool pushOn = true;
  List<Map<String, dynamic>> items = const [];
  bool loading = false;
  int? deletingId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotifications());
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    // Push stack removed from the app — keep the toggle off to avoid confusing UX.
    await p.setString(kPushPrefKey, '0');
    if (!mounted) return;
    setState(() => pushOn = false);
  }

  Future<void> _setPush(bool v) async {
    final api = context.read<ApiClient>();
    if (v) {
      // Push (FCM) removed from the app build — keep toggle off and explain.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push в этом билде недоступен (Firebase удалён). История уведомлений ниже работает.'),
          ),
        );
      }
      return;
    }

    final p = await SharedPreferences.getInstance();
    await p.setString(kPushPrefKey, '0');
    if (!mounted) return;
    setState(() => pushOn = false);
    await PushService.instance.unregisterFromServer(api);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Push выключен')),
      );
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _loadNotifications() async {
    final api = context.read<ApiClient>();
    setState(() => loading = true);
    try {
      final res = await api.get('me/notifications/?limit=50');
      if (!mounted) return;
      if (res.statusCode == 401) {
        final session = context.read<SessionController>();
        final nav = Navigator.of(context);
        await session.logout();
        if (!mounted) return;
        _snack('Сессия истекла. Войдите снова.', error: true);
        nav.pushReplacementNamed('/login');
        return;
      }
      if (res.statusCode != 200) {
        setState(() => items = const []);
        return;
      }
      final j = jsonDecode(res.body);
      final list = j is Map && j['results'] is List
          ? (j['results'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      setState(() => items = list);
    } catch (_) {
      if (mounted) setState(() => items = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final api = context.read<ApiClient>();
    try {
      final res = await api.post('me/notifications/', body: {'all': true});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception();
      _snack('Отмечено как прочитано');
      await _loadNotifications();
    } catch (_) {
      _snack('Не удалось обновить', error: true);
    }
  }

  Future<void> _delete(int id) async {
    setState(() => deletingId = id);
    final api = context.read<ApiClient>();
    try {
      final res = await api.delete('me/notifications/$id/');
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) throw Exception();
      setState(() => items = items.where((e) => (e['id'] as num?)?.toInt() != id).toList());
      _snack('Удалено');
    } catch (_) {
      _snack('Не удалось удалить', error: true);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  int get _unread => items.where((e) => e['read_at'] == null || (e['read_at'] as String).isEmpty).length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Назад',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Уведомления',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Мобильные push (FCM) в этом билде отключены. Ниже — история уведомлений с сервера (как во вебе).',
                style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: cs.primary, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Push-уведомления', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            Text(
                              'Раньше здесь подключался push через Firebase — сейчас он убран из проекта.',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(value: pushOn, onChanged: (v) => _setPush(v)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'История',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
                  ),
                  const Spacer(),
                  if (_unread > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('Непрочитано: $_unread', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        visualDensity: VisualDensity.compact,
                        shape: AppShape.roundedRect,
                      ),
                    ),
                  TextButton(onPressed: loading ? null : _loadNotifications, child: const Text('Обновить')),
                  TextButton(onPressed: _unread == 0 ? null : _markAllRead, child: const Text('Прочитать всё')),
                ],
              ),
              const SizedBox(height: 8),
              if (loading && items.isEmpty) const SkeletonCardList(cards: 5)
else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text('Пока нет уведомлений', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                )
              else
                ...items.map((n) => _NotifTile(
                      item: n,
                      busy: deletingId == (n['id'] as num?)?.toInt(),
                      onDelete: () async {
                        final id = (n['id'] as num?)?.toInt();
                        if (id == null) return;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить уведомление?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                            ],
                          ),
                        );
                        if (ok == true) await _delete(id);
                      },
                      onOpenLink: (route) {
                        Navigator.of(context).pushNamed(route);
                      },
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    required this.item,
    required this.busy,
    required this.onDelete,
    required this.onOpenLink,
  });

  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onDelete;
  final void Function(String route) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = (item['title'] ?? 'Уведомление').toString();
    final body = _cleanBody(item['body']?.toString());
    final created = _fmtDt(item['created_at']?.toString());
    final read = item['read_at'] != null && (item['read_at'] as String).isNotEmpty;
    final link = _linkForType(item['type']?.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: cs.onSurface.withValues(alpha: read ? 0.75 : 1),
                          ),
                        ),
                      ),
                      if (!read)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'NEW',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: cs.onPrimaryContainer),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  onPressed: busy ? null : onDelete,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.delete_outline_rounded, color: cs.error),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(created, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.85))),
                if (link != null) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => onOpenLink(link.route),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(link.label),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
