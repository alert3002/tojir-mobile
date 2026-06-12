/// Безопасный разбор чисел из JSON (API иногда отдаёт String вместо num).
double? parseJsonDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(' ', '').replaceAll(',', '.'));
}

int? parseJsonInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}
