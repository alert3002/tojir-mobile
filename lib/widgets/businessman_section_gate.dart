import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../utils/permissions.dart';

/// Блокирует любые именованные маршруты (кроме разрешённых в [canAccessSection]), если у бизнесмена ещё нет склада.
class BusinessmanSectionGate extends StatelessWidget {
  const BusinessmanSectionGate({super.key, required this.sectionKey, required this.child});

  final String sectionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    if (u != null &&
        (u['role'] as String?) == 'businessman' &&
        !businessmanHasWarehouse(u) &&
        !canAccessSection(u, sectionKey, null)) {
      return const _WarehouseRequiredPage();
    }
    return child;
  }
}

class _WarehouseRequiredPage extends StatelessWidget {
  const _WarehouseRequiredPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Нужен склад'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warehouse_outlined, size: 56, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                'Сначала укажите склад в профиле (название и адрес). До этого раздел недоступен.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
