/// Форматирование чисел как на вебе (`toLocaleString('ru-RU')`).
String formatRuInt(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return negative ? '-${buf.toString()}' : buf.toString();
}

String formatRuMoney(num value, {int fractionDigits = 0, String suffix = ''}) {
  final n = value.toDouble();
  final parts = n.toStringAsFixed(fractionDigits).split('.');
  final intPart = formatRuInt(int.tryParse(parts[0]) ?? 0);
  if (fractionDigits == 0) return suffix.isEmpty ? intPart : '$intPart $suffix';
  final dec = parts.length > 1 ? parts[1] : '0'.padRight(fractionDigits, '0');
  final body = '$intPart,${dec.padRight(fractionDigits, '0').substring(0, fractionDigits)}';
  return suffix.isEmpty ? body : '$body $suffix';
}
