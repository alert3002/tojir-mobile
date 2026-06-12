import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

String? _telUri(String? phoneKey) {
  if (phoneKey == null || phoneKey.isEmpty) return null;
  final d = phoneKey.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('992')) return 'tel:+$d';
  if (d.length == 9 && d.startsWith('9')) return 'tel:+992$d';
  return 'tel:+$d';
}

Future<void> _openTel(String? phoneKey) async {
  final uriStr = _telUri(phoneKey);
  if (uriStr == null) return;
  final uri = Uri.parse(uriStr);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Map<String, dynamic>> clients = const [];
  bool truncated = false;
  bool loading = true;
  final TextEditingController searchCtrl = TextEditingController();
  String search = '';

  @override
  void initState() {
    super.initState();
    searchCtrl.addListener(() {
      final v = searchCtrl.text;
      if (v != search) setState(() => search = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await context.read<ApiClient>().get('inventory/clients/purchases-summary/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        _snack('Не удалось загрузить клиентов', error: true);
        setState(() {
          clients = const [];
          truncated = false;
        });
        return;
      }
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (d['clients'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        clients = list;
        truncated = d['truncated'] == true;
      });
    } catch (_) {
      if (mounted) {
        _snack('Не удалось загрузить клиентов', error: true);
        setState(() {
          clients = const [];
          truncated = false;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  List<Map<String, dynamic>> _filtered() {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return clients;
    return clients.where((c) {
      final debts = (c['debt_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final debtStr = debts.map((x) => '${x['amount']} ${x['currency']}').join(' ');
      final purchases = (c['purchases'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final purchaseBlob = purchases
          .map((p) => '${p['product_name']} ${p['outlet_name']} ${p['warehouse_name']}')
          .join(' ');
      final blob = [
        c['name'],
        c['phone_key'],
        debtStr,
        purchaseBlob,
      ].join(' ').toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'sales', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
    }

    final filtered = _filtered();

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              Row(
                children: [
                  Icon(Icons.groups_outlined, size: 26, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Клиенты',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Покупатели с указанным телефоном в продаже: имя, номер, товар, склад и магазин по каждой продаже.',
                style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: AppShape.br,
                  color: cs.surfaceContainerLow,
                  border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.18 : 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Поиск по имени, телефону, товару, магазину…',
                    hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              if (truncated) ...[
                const SizedBox(height: 12),
                Text(
                  'Показаны не все продажи (лимит 2500 строк). Уточните фильтры в разделе «Продажа» при необходимости.',
                  style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFFD97706)),
                ),
              ],
              const SizedBox(height: 12),
              if (loading) const SkeletonListBlock(rows: 6)
else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: AppShape.br,
                    color: cs.surfaceContainerHighest.withValues(alpha: dark ? 0.45 : 0.55),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Нет клиентов с телефоном в продажах или ничего не найдено.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                ...filtered.map((c) => _ClientExpansionTile(client: c, cs: cs, dark: dark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientExpansionTile extends StatelessWidget {
  const _ClientExpansionTile({required this.client, required this.cs, required this.dark});

  final Map<String, dynamic> client;
  final ColorScheme cs;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final name = (client['name'] ?? '—').toString();
    final phoneKey = client['phone_key']?.toString();
    final purchases = (client['purchases'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final debts = (client['debt_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tel = _telUri(phoneKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: AppShape.br,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface)),
                const SizedBox(height: 4),
                if (tel != null && phoneKey != null)
                  InkWell(
                    onTap: () => _openTel(phoneKey),
                    child: Text(
                      phoneKey,
                      style: TextStyle(fontSize: 14, color: cs.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                    ),
                  )
                else
                  Text(phoneKey ?? '—', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  'Покупок: ${purchases.length}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (debts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Долг: ${debts.map((x) => '${x['amount']} ${x['currency']}').join(' · ')}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.error),
                  ),
                ],
              ],
            ),
            children: [
              if (purchases.isEmpty)
                Text('Нет покупок', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
              else
                ...purchases.map((p) => _PurchaseLine(p: p, cs: cs)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseLine extends StatelessWidget {
  const _PurchaseLine({required this.p, required this.cs});

  final Map<String, dynamic> p;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final product = (p['product_name'] ?? '—').toString();
    final qty = p['quantity'];
    final unitPrice = p['unit_price'];
    final currency = (p['currency'] ?? '').toString();
    final wh = (p['warehouse_name'] ?? '—').toString();
    final outlet = (p['outlet_name'] ?? '—').toString();
    final sold = (p['sold_at'] ?? '—').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.45), width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.85),
                      borderRadius: AppShape.br,
                    ),
                    child: Text('$qty шт', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                  ),
                  Text(
                    '$unitPrice $currency',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Склад: $wh', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Text('Магазин: $outlet', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Text('Дата: $sold', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
