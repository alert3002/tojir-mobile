import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme/app_brand.dart';

/// AI FAB на главной бизнесмена — как web `AiAssistantFab.jsx` (только home).
class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({super.key});

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AiChatSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSheet,
          customBorder: const CircleBorder(),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final glow = 0.45 + _pulse.value * 0.12;
              return DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF38BDF8), Color(0xFF6366F1), Color(0xFFA855F7)],
                    stops: [0.0, 0.52, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.white.withValues(alpha: 0.92), spreadRadius: 0, blurRadius: 0),
                    BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: glow), blurRadius: 28, offset: const Offset(0, 8)),
                    BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: child,
              );
            },
            child: const Center(
              child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet();

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  final _input = TextEditingController();
  final _messages = <Map<String, String>>[
    {
      'role': 'assistant',
      'text': 'Салом! Я TOJIr AI — отвечаю по вашему складу: продажи, расходы, остатки. Задайте вопрос.',
    },
  ];
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _messages.add({'role': 'user', 'text': q});
      _loading = true;
      _input.clear();
    });
    try {
      final res = await context.read<ApiClient>().post(
        'inventory/ai/chat/',
        body: {
          'message': q,
          'history': _messages
              .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
              .map((m) => {'role': m['role'], 'content': m['text']})
              .toList(),
        },
      );
      if (!mounted) return;
      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      final reply = (data is Map ? (data['reply'] ?? data['text'] ?? data['detail']) : null)?.toString() ??
          (res.statusCode == 200 ? 'Готово.' : 'Ошибка ${res.statusCode}');
      setState(() => _messages.add({'role': 'assistant', 'text': reply}));
    } catch (e) {
      if (mounted) setState(() => _messages.add({'role': 'assistant', 'text': 'Ошибка: $e'}));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 3, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(99))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, color: AppBrand.primaryBlue),
                const SizedBox(width: 8),
                Text('TOJIr AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final user = m['role'] == 'user';
                return Align(
                  alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
                    decoration: BoxDecoration(
                      color: user ? AppBrand.primaryBlue.withValues(alpha: 0.15) : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m['text'] ?? '', style: TextStyle(fontSize: 14, color: cs.onSurface, height: 1.35)),
                  ),
                );
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(hintText: 'Ваш вопрос…', isDense: true),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : () => _send(), child: const Icon(Icons.send_rounded, size: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
