import 'package:flutter/material.dart';

import '../theme/app_brand.dart';
import '../utils/number_format.dart';

/// Hero-блок «Склад и остатки» — как web `.tojir-warehouse-hero`.
class WarehouseHero extends StatelessWidget {
  const WarehouseHero({
    super.key,
    required this.dark,
    required this.cs,
    required this.isSeller,
    required this.warehouseName,
    required this.storeCount,
    required this.stats,
    required this.showTrash,
    required this.onArrivals,
    required this.onTransfers,
    required this.onStores,
  });

  final bool dark;
  final ColorScheme cs;
  final bool isSeller;
  final String warehouseName;
  final int storeCount;
  final WarehouseStats? stats;
  final bool showTrash;
  final VoidCallback onArrivals;
  final VoidCallback onTransfers;
  final VoidCallback onStores;

  @override
  Widget build(BuildContext context) {
    final cardBg = dark ? const Color(0xFF151D2E) : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: dark ? 0.22 : 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.alphaBlend(const Color(0xFF0EA5E9).withValues(alpha: 0.14), cardBg),
            Color.alphaBlend(const Color(0xFF22C55E).withValues(alpha: 0.08), cardBg),
            cardBg,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.2 : 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF0EA5E9).withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.inbox_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSeller ? 'ОСТАТКИ В МАГАЗИНЕ' : 'СКЛАД И ОСТАТКИ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.04, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(warehouseName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2, color: cs.onSurface)),
                    if (!isSeller && storeCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.storefront_outlined, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            '$storeCount ${storeCount == 1 ? 'магазин' : 'магазинов'}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (stats != null) ...[
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.15,
              children: [
                _HeroStat(label: 'Позиций', value: '${stats!.positions}', dark: dark, cs: cs),
                if (!isSeller)
                  _HeroStat(label: 'На складе', value: '${formatRuInt(stats!.warehouseQty)} шт', dark: dark, cs: cs),
                _HeroStat(
                  label: isSeller
                      ? 'В магазине'
                      : (stats!.storeLabel?.isNotEmpty == true ? stats!.storeLabel! : 'В магазинах'),
                  value: '${formatRuInt(stats!.storeQty)} шт',
                  dark: dark,
                  cs: cs,
                ),
                if (!isSeller)
                  _HeroStat(
                    label: 'Мало (≤5)',
                    value: '${stats!.lowStock}',
                    dark: dark,
                    cs: cs,
                    warn: stats!.lowStock > 0,
                  ),
              ],
            ),
          ],
          if (!isSeller && !showTrash) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _HeroAction(label: 'Поступление', icon: Icons.add_rounded, tone: _HeroActionTone.blue, onTap: onArrivals),
                _HeroAction(label: 'Перемещения', icon: Icons.swap_horiz_rounded, tone: _HeroActionTone.cyan, onTap: onTransfers),
                _HeroAction(label: 'Магазины', icon: Icons.storefront_outlined, tone: _HeroActionTone.indigo, onTap: onStores),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class WarehouseStats {
  const WarehouseStats({
    required this.positions,
    required this.warehouseQty,
    required this.storeQty,
    required this.lowStock,
    required this.stores,
    this.storeLabel,
  });
  final int positions;
  final int warehouseQty;
  final int storeQty;
  final int lowStock;
  final int stores;
  final String? storeLabel;
}

enum _HeroActionTone { blue, cyan, indigo }

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.dark, required this.cs, this.warn = false});
  final String label;
  final String value;
  final bool dark;
  final ColorScheme cs;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: warn ? const Color(0xFFF97316).withValues(alpha: 0.1) : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.85)),
        border: Border.all(color: warn ? const Color(0xFFF97316).withValues(alpha: 0.35) : (dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF0F172A).withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.03, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: warn ? const Color(0xFFFB923C) : cs.onSurface),
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.label, required this.icon, required this.tone, required this.onTap});
  final String label;
  final IconData icon;
  final _HeroActionTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (tone) {
      _HeroActionTone.blue => (const Color(0xFF2563EB), const Color(0xFF3B82F6).withValues(alpha: 0.14), const Color(0xFF3B82F6).withValues(alpha: 0.28)),
      _HeroActionTone.cyan => (const Color(0xFF0284C7), const Color(0xFF0EA5E9).withValues(alpha: 0.14), const Color(0xFF0EA5E9).withValues(alpha: 0.28)),
      _HeroActionTone.indigo => (const Color(0xFF4F46E5), const Color(0xFF6366F1).withValues(alpha: 0.14), const Color(0xFF6366F1).withValues(alpha: 0.28)),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: bg,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Фильтры склада — как web `.tojir-warehouse-filters`.
class WarehouseFiltersCard extends StatelessWidget {
  const WarehouseFiltersCard({
    super.key,
    required this.cs,
    required this.dark,
    required this.child,
  });

  final ColorScheme cs;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark ? AppBrand.darkCard : cs.surface,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

class WarehouseStoreChips extends StatelessWidget {
  const WarehouseStoreChips({
    super.key,
    required this.outlets,
    required this.selectedOutletId,
    required this.canAdd,
    required this.addDisabled,
    required this.onAdd,
    required this.onSelectAll,
    required this.onSelectOutlet,
  });

  final List<Map<String, dynamic>> outlets;
  final int? selectedOutletId;
  final bool canAdd;
  final bool addDisabled;
  final VoidCallback onAdd;
  final VoidCallback onSelectAll;
  final ValueChanged<int> onSelectOutlet;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canAdd)
          _StoreChip(
            label: 'Магазин',
            leading: Icons.add_rounded,
            active: true,
            addStyle: true,
            onTap: addDisabled ? null : onAdd,
          ),
        if (outlets.isNotEmpty)
          _StoreChip(
            label: 'Все',
            active: selectedOutletId == null,
            onTap: onSelectAll,
          ),
        for (final o in outlets)
          _StoreChip(
            label: (o['name'] ?? 'Магазин').toString(),
            active: selectedOutletId == _asInt(o['id']),
            onTap: () {
              final id = _asInt(o['id']);
              if (id != null) onSelectOutlet(id);
            },
          ),
      ],
    );
  }
}

class _StoreChip extends StatelessWidget {
  const _StoreChip({
    required this.label,
    required this.active,
    this.leading,
    this.addStyle = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final IconData? leading;
  final bool addStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;
    if (addStyle) {
      bg = const Color(0xFF2563EB);
      border = const Color(0xFF2563EB);
      fg = Colors.white;
    } else if (active) {
      bg = const Color(0xFF2563EB);
      border = const Color(0xFF2563EB);
      fg = Colors.white;
    } else {
      bg = const Color(0xFF2563EB).withValues(alpha: 0.1);
      border = const Color(0xFF2563EB).withValues(alpha: 0.4);
      fg = const Color(0xFF93C5FD);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: bg,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                Icon(leading, size: 12, color: fg),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class WarehouseTrashTabs extends StatelessWidget {
  const WarehouseTrashTabs({super.key, required this.showTrash, required this.onChanged});
  final bool showTrash;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _TabBtn(
              label: 'Товары',
              active: !showTrash,
              roundedLeft: true,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _TabBtn(
              label: 'Корзина',
              active: showTrash,
              roundedRight: true,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.active,
    required this.onTap,
    this.roundedLeft = false,
    this.roundedRight = false,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool roundedLeft;
  final bool roundedRight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: active ? const Color(0xFF2563EB) : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 28,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : (dark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка товара на мобильном складе — как web `.tojir-warehouse-item`.
class WarehouseMobileProductCard extends StatelessWidget {
  const WarehouseMobileProductCard({
    super.key,
    required this.record,
    required this.cs,
    required this.dark,
    required this.warehouseOutlets,
    required this.showTrash,
    required this.isSeller,
    required this.canSeeWarehouseQty,
    required this.unitLabel,
    this.filterOutletId,
    this.usdToTjs = 11.5,
    this.onTap,
    this.onDistribute,
    this.onEdit,
    required this.onDelete,
    this.onRestore,
  });

  final Map<String, dynamic> record;
  final ColorScheme cs;
  final bool dark;
  final List<Map<String, dynamic>> warehouseOutlets;
  final bool showTrash;
  final bool isSeller;
  final bool canSeeWarehouseQty;
  final String Function(String?) unitLabel;
  final int? filterOutletId;
  final double usdToTjs;
  final VoidCallback? onTap;
  final VoidCallback? onDistribute;
  final VoidCallback? onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    final stock = _outletStock(record, warehouseOutlets, filterOutletId);
    final whQty = _asDouble(record['quantity']) ?? 0;
    final storeQty = filterOutletId != null
        ? (_asDouble(record['outlet_stock_quantity']) ?? (stock.lines.isNotEmpty ? stock.lines.first.qty : 0))
        : stock.inStores;
    final total = canSeeWarehouseQty ? whQty + storeQty : storeQty;
    final u = unitLabel((record['unit'] ?? 'pcs').toString());
    final saleTjs = _asDouble(record['sale_price']) ?? 0;
    final isLow = !isSeller && whQty > 0 && whQty <= 5;
    final showOutlets = stock.lines.isNotEmpty;
    final showDistribute = !isSeller && !showTrash && canSeeWarehouseQty && whQty > 0 && warehouseOutlets.isNotEmpty && onDistribute != null;
    final fxUsd = usdToTjs > 0 && saleTjs > 0 ? saleTjs / usdToTjs : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isLow
                ? Color.alphaBlend(const Color(0xFFF97316).withValues(alpha: 0.08), dark ? AppBrand.darkRow : cs.surfaceContainer)
                : (dark ? AppBrand.darkRow : cs.surfaceContainer),
            border: Border.all(color: isLow ? const Color(0xFFF97316).withValues(alpha: 0.42) : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      (record['name'] ?? '—').toString(),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: cs.onSurface),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showTrash && onRestore != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Восстановить',
                          onPressed: onRestore,
                          icon: const Icon(Icons.undo_rounded, size: 18),
                        ),
                      if (!showTrash && !isSeller && onEdit != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Изменить',
                          onPressed: onEdit,
                          icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                        ),
                      if (!isSeller || showTrash)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: showTrash ? 'Удалить навсегда' : 'Удалить',
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        ),
                    ],
                  ),
                ],
              ),
              if ((record['model'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(record['model'].toString(), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
              if (_hasTags(record)) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: _buildTags(record, cs)),
              ],
              const SizedBox(height: 8),
              if (isSeller)
                _SellerStockBar(
                  label: warehouseOutlets.length == 1 ? (warehouseOutlets.first['name'] ?? 'В магазине').toString() : 'В магазинах',
                  qty: storeQty,
                  unit: u,
                  price: saleTjs,
                  fxUsd: fxUsd,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _MetaPair(
                        dark: dark,
                        label: 'продажа',
                        value: saleTjs > 0 ? '${saleTjs.round()} с.' : '—',
                        fxLine: fxUsd != null ? '≈ ${fxUsd.toStringAsFixed(2).replaceAll('.', ',')} USD' : null,
                      ),
                    ),
                    if (canSeeWarehouseQty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetaPair(
                          dark: dark,
                          label: 'склад',
                          value: '${whQty % 1 == 0 ? whQty.toInt() : whQty} $u',
                        ),
                      ),
                    ],
                  ],
                ),
              if (showOutlets) ...[
                const SizedBox(height: 8),
                Text(
                  filterOutletId != null
                      ? (stock.lines.first.name.toUpperCase())
                      : (isSeller ? 'ПО МАГАЗИНАМ' : 'МАГАЗИНЫ'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.04, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.6,
                  children: [
                    for (final line in stock.lines)
                      _OutletChip(name: line.name, qty: line.qty, unit: u, dark: dark),
                  ],
                ),
              ],
              if (!isSeller) ...[
                const SizedBox(height: 8),
                _MetaPair(dark: dark, label: 'всего', value: '${total % 1 == 0 ? total.toInt() : total} $u', strong: true, wide: true),
              ],
              if (showDistribute) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onDistribute,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Распределить', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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

class _SellerStockBar extends StatelessWidget {
  const _SellerStockBar({
    required this.label,
    required this.qty,
    required this.unit,
    required this.price,
    this.fxUsd,
  });
  final String label;
  final double qty;
  final String unit;
  final double price;
  final double? fxUsd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [const Color(0xFF2563EB).withValues(alpha: 0.18), const Color(0xFF22C55E).withValues(alpha: 0.12)],
        ),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: Colors.white.withValues(alpha: 0.55))),
                Text(
                  '${qty % 1 == 0 ? qty.toInt() : qty} $unit',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFFF1F5F9), height: 1.1),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price > 0 ? '${price.round()} с.' : '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF86EFAC))),
              if (fxUsd != null)
                Text(
                  '≈ ${fxUsd!.toStringAsFixed(2).replaceAll('.', ',')} USD',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.55)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPair extends StatelessWidget {
  const _MetaPair({
    required this.dark,
    required this.label,
    required this.value,
    this.fxLine,
    this.strong = false,
    this.wide = false,
  });
  final bool dark;
  final String label;
  final String value;
  final String? fxLine;
  final bool strong;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: strong ? 13 : 12,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                    color: dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                  ),
                ),
                if (fxLine != null)
                  Text(
                    fxLine!,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutletChip extends StatelessWidget {
  const _OutletChip({required this.name, required this.qty, required this.unit, required this.dark});
  final String name;
  final double qty;
  final String unit;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
          Text('${qty % 1 == 0 ? qty.toInt() : qty} $unit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

class _OutletStockLine {
  const _OutletStockLine({required this.id, required this.name, required this.qty});
  final dynamic id;
  final String name;
  final double qty;
}

class _OutletStockResult {
  const _OutletStockResult({required this.lines, required this.inStores});
  final List<_OutletStockLine> lines;
  final double inStores;
}

_OutletStockResult _outletStock(Map<String, dynamic> record, List<Map<String, dynamic>> outlets, [int? filterOutletId]) {
  final summary = (record['outlets_summary'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
  final byId = <String, double>{};
  for (final o in summary) {
    final id = o['outlet_id']?.toString() ?? o['id']?.toString() ?? '';
    byId[id] = _asDouble(o['quantity']) ?? 0;
  }
  var inStores = 0.0;
  final lines = <_OutletStockLine>[];
  for (final o in outlets) {
    final id = o['id']?.toString() ?? '';
    final oid = _asInt(o['id']);
    if (filterOutletId != null && oid != filterOutletId) continue;
    final q = byId[id] ?? 0;
    inStores += q;
    lines.add(_OutletStockLine(id: o['id'], name: (o['name'] ?? 'Магазин').toString(), qty: q));
  }
  return _OutletStockResult(lines: lines, inStores: inStores);
}

bool _hasTags(Map<String, dynamic> record) {
  for (final k in ['brand', 'color', 'memory', 'ram', 'size']) {
    if ((record[k] ?? '').toString().trim().isNotEmpty) return true;
  }
  return false;
}

List<Widget> _buildTags(Map<String, dynamic> record, ColorScheme cs) {
  Widget tag(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (color ?? cs.surfaceContainerHighest).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
      );
  final out = <Widget>[];
  if ((record['brand'] ?? '').toString().isNotEmpty) out.add(tag(record['brand'].toString()));
  if ((record['color'] ?? '').toString().isNotEmpty) out.add(tag(record['color'].toString()));
  if ((record['memory'] ?? '').toString().isNotEmpty) out.add(tag(record['memory'].toString(), color: Colors.blue.withValues(alpha: 0.2)));
  if ((record['ram'] ?? '').toString().isNotEmpty) out.add(tag(record['ram'].toString(), color: Colors.indigo.withValues(alpha: 0.2)));
  if ((record['size'] ?? '').toString().isNotEmpty) out.add(tag(record['size'].toString(), color: Colors.purple.withValues(alpha: 0.2)));
  return out;
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

double? _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}
