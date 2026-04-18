import 'package:flutter/material.dart';

/// Локальные границы «сегодня», «текущая неделя (пн—сегодня)», «текущий месяц».
class DateRangePresets {
  DateRangePresets._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Один календарный день (сегодня).
  static DateTimeRange todayLocal() {
    final t = dateOnly(DateTime.now());
    return DateTimeRange(start: t, end: t);
  }

  /// С понедельника текущей недели по сегодня (ISO weekday: пн = 1).
  static DateTimeRange weekToTodayLocal() {
    final end = dateOnly(DateTime.now());
    final monday = end.subtract(Duration(days: end.weekday - 1));
    return DateTimeRange(start: monday, end: end);
  }

  /// С 1-го числа месяца по сегодня.
  static DateTimeRange monthToTodayLocal() {
    final end = dateOnly(DateTime.now());
    final start = DateTime(end.year, end.month, 1);
    return DateTimeRange(start: start, end: end);
  }

  static DateTimeRange? rangeForPreset(String kind) {
    switch (kind) {
      case 'today':
        return todayLocal();
      case 'week':
        return weekToTodayLocal();
      case 'month':
        return monthToTodayLocal();
      default:
        return null;
    }
  }
}
