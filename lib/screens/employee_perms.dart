import 'package:flutter/material.dart';

class SellerSection {
  const SellerSection({required this.key, required this.label});

  final String key;
  final String label;
}

const sellerSections = <SellerSection>[
  SellerSection(key: 'sales', label: 'Продажа'),
  SellerSection(key: 'arrivals', label: 'Поступление'),
  SellerSection(key: 'returns', label: 'Возвраты'),
  SellerSection(key: 'warehouse', label: 'Склад'),
  SellerSection(key: 'transfers', label: 'Перемещения'),
  SellerSection(key: 'debts', label: 'Долги (Насия)'),
  SellerSection(key: 'expenses', label: 'Расходы'),
  SellerSection(key: 'history', label: 'История'),
  SellerSection(key: 'stores', label: 'Магазины'),
  SellerSection(key: 'employees', label: 'Сотрудники'),
  SellerSection(key: 'referral', label: 'Реферал'),
  SellerSection(key: 'tariffs', label: 'Тарифы'),
  SellerSection(key: 'course', label: 'Курс'),
];

const permActions = <MapEntry<String, String>>[
  MapEntry('view', 'Просмотр'),
  MapEntry('create', 'Добавить'),
  MapEntry('edit', 'Изменить'),
  MapEntry('delete', 'Удалить'),
];

Map<String, dynamic> _normalizePerms(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

/// Editor for allowed_perms used by employees add/edit.
class EmployeePermsEditor extends StatelessWidget {
  const EmployeePermsEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final perms = _normalizePerms(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Доступ (по действиям)',
          style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          'Выберите действия по каждому разделу. Если ничего не отмечено — у продавца не будет доступа к разделу.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 10),
        ...sellerSections.map((sec) {
          final rawSec = perms[sec.key];
          final secPerms = _normalizePerms(rawSec);

          bool isChecked(String action) => secPerms[action] == true;

          void toggle(String action, bool next) {
            final nextPerms = Map<String, dynamic>.from(perms);
            final nextSec = Map<String, dynamic>.from(secPerms);
            nextSec[action] = next;
            nextPerms[sec.key] = nextSec;
            onChanged(nextPerms);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sec.label, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in permActions)
                      FilterChip(
                        label: Text(a.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        selected: isChecked(a.key),
                        onSelected: (v) => toggle(a.key, v),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

