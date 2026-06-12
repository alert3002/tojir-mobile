import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';

const _cardBg = Color(0xFF151D2E);

class PlatformUsersScreen extends StatelessWidget {
  const PlatformUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Управление пользователями', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Text(
                  'Раздел в разработке: список пользователей, роли (Платформа, Бизнесмен, Продавец), блокировка.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
