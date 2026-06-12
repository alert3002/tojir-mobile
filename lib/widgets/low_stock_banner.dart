import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';

/// Баннер «Мало товара на складе» — как web `LowStockBanner.jsx`.
class LowStockBanner extends StatefulWidget {
  const LowStockBanner({super.key, required this.user, this.onGoWarehouse});

  final Map<String, dynamic>? user;
  final VoidCallback? onGoWarehouse;

  @override
  State<LowStockBanner> createState() => _LowStockBannerState();
}

class _LowStockBannerState extends State<LowStockBanner> {
  int _count = 0;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant LowStockBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?['warehouse'] != widget.user?['warehouse']) _load();
  }

  Future<void> _load() async {
    final user = widget.user;
    final wh = user?['warehouse'];
    if (user?['role'] != 'businessman' || wh == null) {
      if (mounted) setState(() => _count = 0);
      return;
    }
    try {
      final res = await context.read<ApiClient>().get('inventory/products/?warehouse=$wh&low_stock=5');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final list = d is List ? d : (d is Map ? (d['results'] ?? []) : []);
        final count = list is List ? list.length : 0;
        final key = 'tojir_low_stock_closed_${wh}_$count';
        final p = await SharedPreferences.getInstance();
        final closed = count > 0 && p.getString(key) == '1';
        setState(() {
          _count = count;
          _closed = closed;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _count = 0);
    }
  }

  Future<void> _dismiss() async {
    final wh = widget.user?['warehouse'];
    if (wh != null && _count > 0) {
      final p = await SharedPreferences.getInstance();
      await p.setString('tojir_low_stock_closed_${wh}_$_count', '1');
    }
    if (mounted) setState(() => _closed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_count <= 0 || _closed) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Material(
      color: const Color(0x1AFBBF24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: const Color(0xFFFBBF24).withValues(alpha: dark ? 0.22 : 0.2))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.warning_amber_rounded, size: 15, color: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12, height: 1.35, color: textColor),
                        children: [
                          const TextSpan(text: 'Мало товара на складе: '),
                          TextSpan(text: '$_count', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const TextSpan(text: ' поз. (≤5 шт)'),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onGoWarehouse ?? () => Navigator.of(context).pushNamed('/warehouse'),
                      child: Text(
                        'На склад',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _dismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
