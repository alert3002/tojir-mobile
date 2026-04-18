import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';

/// Временно: детальная карточка товара (как /warehouse/product/:id на web).
class WarehouseProductPlaceholderScreen extends StatelessWidget {
  const WarehouseProductPlaceholderScreen({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Товар #$productId\n(скоро — как на сайте)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}
