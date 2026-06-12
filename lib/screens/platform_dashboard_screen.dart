import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class PlatformDashboardScreen extends StatefulWidget {
  const PlatformDashboardScreen({super.key});

  @override
  State<PlatformDashboardScreen> createState() => _PlatformDashboardScreenState();
}

class _PlatformDashboardScreenState extends State<PlatformDashboardScreen> {
  bool loading = true;
  Map<String, dynamic>? stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().get('inventory/platform/stats/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        setState(() => stats = j is Map<String, dynamic> ? j : null);
      }
    } catch (_) {
      if (mounted) setState(() => stats = null);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _intVal(String key) {
    final v = stats?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              Text('Панель платформы TOJIr', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 16),
              if (loading)
                const SkeletonListBlock(rows: 4)
              else ...[
                Row(
                  children: [
                    Expanded(child: _StatCard(icon: Icons.people_outline_rounded, label: 'Пользователи', value: _intVal('users_count'))),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCard(icon: Icons.inventory_2_outlined, label: 'Склады', value: _intVal('warehouses_count'))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _StatCard(icon: Icons.storefront_outlined, label: 'Магазины', value: _intVal('outlets_count'))),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCard(icon: Icons.shopping_cart_outlined, label: 'Продажи', value: _intVal('sales_count'))),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Управление', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushNamed('/platform/users'),
                        style: FilledButton.styleFrom(backgroundColor: _blue),
                        child: const Text('Модераторы и пользователи'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pushNamed('/tariffs'),
                        child: const Text('Тарифы'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 22),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
