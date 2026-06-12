import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class ModeratorsScreen extends StatefulWidget {
  const ModeratorsScreen({super.key});

  @override
  State<ModeratorsScreen> createState() => _ModeratorsScreenState();
}

class _ModeratorsScreenState extends State<ModeratorsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> rows = const [];
  int? revokingId;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  bool get _isBusinessman => (_user?['role'] as String?) == 'businessman';
  bool get _isPlatform => (_user?['role'] as String?) == 'platform';
  bool get _canManage => _isBusinessman && businessmanHasWarehouse(_user);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final u = _user;
    if (u == null || (!_isBusinessman && !_isPlatform)) {
      setState(() {
        rows = const [];
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().get('me/moderators/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        setState(() => rows = (j is List) ? j.cast<Map<String, dynamic>>() : const []);
      } else {
        setState(() => rows = const []);
      }
    } catch (_) {
      if (mounted) setState(() => rows = const []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> r) async {
    final id = r['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Снять модератора?'),
        content: Text('${r['phone']} перейдёт в роль «Клиент» и потеряет доступ к рефералам бизнесмена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Снять'),
          ),
        ],
      ),
    );
    if (ok != true || id == null) return;
    setState(() => revokingId = id as int);
    try {
      final res = await context.read<ApiClient>().patch('me/moderators/$id/revoke/', body: {});
      if (!mounted) return;
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        throw Exception(body is Map ? body['detail']?.toString() ?? 'Ошибка' : 'Ошибка');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Модератор снят')));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_canManage && !_isPlatform) {
      return AppScaffold(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Модераторы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                const SizedBox(height: 16),
                Text('Доступ только у бизнесмена со складом или платформы.', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Модераторы', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface))),
                  if (_isBusinessman)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pushNamed('/moderators/add'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Пригласить'),
                      style: FilledButton.styleFrom(backgroundColor: _blue, visualDensity: VisualDensity.compact),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Модератор видит в приложении реферальную статистику так же, как вы (приглашённые и бонусы).',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 16),
              if (loading)
                const SkeletonListBlock(rows: 4)
              else if (rows.isEmpty)
                Text('Нет модераторов', style: TextStyle(color: cs.onSurfaceVariant))
              else
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ModeratorCard(
                    row: rows[i],
                    showAddedBy: _isPlatform,
                    canRevoke: _isBusinessman,
                    revoking: revokingId == rows[i]['id'],
                    onRevoke: () => _revoke(rows[i]),
                  ),
                ],
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Navigator.of(context).pushNamed('/employees'), child: const Text('К сотрудникам')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeratorCard extends StatelessWidget {
  const _ModeratorCard({
    required this.row,
    required this.showAddedBy,
    required this.canRevoke,
    required this.revoking,
    required this.onRevoke,
  });

  final Map<String, dynamic> row;
  final bool showAddedBy;
  final bool canRevoke;
  final bool revoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = [row['first_name'], row['last_name']].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((row['phone'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          if (name.isNotEmpty) Text(name, style: TextStyle(color: cs.onSurfaceVariant)),
          if (showAddedBy) Text('Закреплён за: ${row['added_by_phone'] ?? '—'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (canRevoke) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: revoking ? null : onRevoke,
              icon: revoking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.person_remove_outlined, size: 18, color: cs.error),
              label: Text('Снять', style: TextStyle(color: cs.error)),
            ),
          ],
        ],
      ),
    );
  }
}
