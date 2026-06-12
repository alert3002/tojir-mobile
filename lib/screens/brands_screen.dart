import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> brands = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().get('inventory/brands/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        setState(() {
          brands = (j is List) ? j.cast<Map<String, dynamic>>() : const [];
        });
      } else {
        setState(() => brands = const []);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось загрузить бренды')));
        setState(() => brands = const []);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
              Text('Бренды', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Список брендов товаров', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (loading)
                const SkeletonListBlock(rows: 5)
              else if (brands.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Бренды не указаны в карточках товаров',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                for (var i = 0; i < brands.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _BrandCard(
                    name: (brands[i]['name'] ?? '').toString(),
                    onOpenWarehouse: () {
                      final name = (brands[i]['name'] ?? '').toString();
                      Navigator.of(context).pushNamed('/warehouse', arguments: {'brand': name});
                    },
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.name, required this.onOpenWarehouse});
  final String name;
  final VoidCallback onOpenWarehouse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _blue.withValues(alpha: 0.3)),
            ),
            child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          TextButton(onPressed: onOpenWarehouse, child: const Text('Товары на складе')),
        ],
      ),
    );
  }
}
