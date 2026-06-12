import 'package:flutter/material.dart';

import '../utils/offline_queue.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

String _methodLabel(String m) {
  const map = {'POST': 'Создание', 'PATCH': 'Изменение', 'PUT': 'Сохранение', 'DELETE': 'Удаление'};
  return map[m] ?? m;
}

String _urlLabel(String url) {
  if (url.contains('/sales/batch')) return 'Продажа';
  if (url.contains('/arrivals')) return 'Поступление';
  if (url.contains('/expenses')) return 'Расход';
  if (url.contains('/transfers')) return 'Перемещение';
  if (url.contains('/returns')) return 'Возврат';
  final parts = url.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) return parts.sublist(parts.length - 2).join('/');
  return url.isEmpty ? '—' : url;
}

String _formatDate(int? ms) {
  if (ms == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year} $hh:$min';
}

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  bool loading = true;
  List<OfflineQueueItem> items = const [];
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() => loading = true);
    final list = await getQueueItems();
    if (mounted) {
      setState(() {
        items = list;
        loading = false;
      });
    }
  }

  Future<void> _remove(int id) async {
    await removeQueueItem(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Удалено из очереди')));
    _reload();
  }

  Future<void> _syncAll() async {
    setState(() => syncing = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Синхронизация офлайн-очереди в мобильном приложении скоро будет доступна')),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              Text('Офлайн-очередь', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(
                'Записи, сохранённые без интернета. Отправятся автоматически при подключении.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_rounded, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Интернет подключён')),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${items.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: items.isEmpty || syncing ? null : _syncAll,
                icon: syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_sync_rounded, size: 18),
                label: const Text('Отправить сейчас'),
                style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size(double.infinity, 44)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: loading ? null : _reload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Обновить'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
              ),
              const SizedBox(height: 16),
              if (loading)
                const SkeletonListBlock(rows: 4)
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Очередь пуста', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                )
              else
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _QueueCard(item: items[i], onRemove: () => _remove(items[i].id)),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.item, required this.onRemove});
  final OfflineQueueItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = item.label.isNotEmpty ? item.label : _urlLabel(item.url);
    Color statusColor;
    String statusText;
    if (item.failed) {
      statusColor = cs.error;
      statusText = 'Ошибка';
    } else if (item.attempts > 0) {
      statusColor = Colors.orange;
      statusText = 'Повтор';
    } else {
      statusColor = _blue;
      statusText = 'Ожидает';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.failed ? cs.error.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(_methodLabel(item.method), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Дата: ${_formatDate(item.createdAt)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (item.lastError != null && item.lastError!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Ошибка: ${item.lastError}', style: TextStyle(fontSize: 12, color: cs.error)),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Удалить из очереди'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ],
      ),
    );
  }
}
