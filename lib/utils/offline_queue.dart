import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'tojir_offline_queue_v1';

class OfflineQueueItem {
  OfflineQueueItem({
    required this.id,
    required this.method,
    required this.url,
    this.label = '',
    this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.failed = false,
  });

  final int id;
  final String method;
  final String url;
  final String label;
  final int? createdAt;
  final int attempts;
  final String? lastError;
  final bool failed;

  factory OfflineQueueItem.fromJson(Map<String, dynamic> j) => OfflineQueueItem(
        id: j['id'] as int? ?? 0,
        method: (j['method'] ?? 'POST').toString(),
        url: (j['url'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        createdAt: j['createdAt'] as int?,
        attempts: j['attempts'] as int? ?? 0,
        lastError: j['lastError']?.toString(),
        failed: j['failed'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        'label': label,
        'createdAt': createdAt,
        'attempts': attempts,
        'lastError': lastError,
        'failed': failed,
      };
}

Future<List<OfflineQueueItem>> getQueueItems() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_storageKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => OfflineQueueItem.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
  } catch (_) {
    return [];
  }
}

Future<void> removeQueueItem(int id) async {
  final items = await getQueueItems();
  final next = items.where((i) => i.id != id).map((e) => e.toJson()).toList();
  final p = await SharedPreferences.getInstance();
  await p.setString(_storageKey, jsonEncode(next));
}
