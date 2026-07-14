import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

/// Проверяет версию при старте (и при resume) и показывает диалог обновления.
mixin AppUpdateChecker<T extends StatefulWidget> on State<T> {
  bool _updateDialogVisible = false;

  @protected
  void scheduleAppUpdateCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAppUpdateCheck());
  }

  Future<void> _runAppUpdateCheck() async {
    if (!mounted || _updateDialogVisible) return;
    final info = await AppUpdateService.check();
    if (!mounted || info == null) return;
    _updateDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !info.force,
        builder: (ctx) => PopScope(
          canPop: !info.force,
          child: AlertDialog(
            title: Text(info.force ? 'Требуется обновление' : 'Доступно обновление'),
            content: Text(
              '${info.message}\n\n'
              'Ваша версия: ${info.currentVersion}\n'
              'Новая версия: ${info.latestVersion}',
            ),
            actions: [
              if (!info.force)
                TextButton(
                  onPressed: () async {
                    await AppUpdateService.dismissOptional(info.latestVersion);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Позже'),
                ),
              FilledButton(
                onPressed: () async {
                  await AppUpdateService.openStore(info.storeUrl);
                  if (!info.force && ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('Обновить'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _updateDialogVisible = false;
    }
  }
}
