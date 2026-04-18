import 'package:flutter/material.dart';

import '../theme/app_shape.dart';

/// Быстрый выбор: Сегодня, Неделя, Месяц, Период (кастом — через [onPeriod]).
class QuickDateRangeChips extends StatelessWidget {
  const QuickDateRangeChips({
    super.key,
    required this.colorScheme,
    required this.selected,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
    required this.onPeriod,
  });

  final ColorScheme colorScheme;
  final String? selected;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;
  final VoidCallback onPeriod;

  @override
  Widget build(BuildContext context) {
    ChoiceChip chip(String id, String label, VoidCallback onTap) {
      return ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        selected: selected == id,
        onSelected: (v) {
          if (v) onTap();
        },
        shape: AppShape.roundedRect,
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.28)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selectedColor: colorScheme.primaryContainer,
        checkmarkColor: colorScheme.onPrimaryContainer,
        labelStyle: TextStyle(
          color: selected == id ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('today', 'Сегодня', onToday),
        chip('week', 'Неделя', onWeek),
        chip('month', 'Месяц', onMonth),
        chip('period', 'Период', onPeriod),
      ],
    );
  }
}
