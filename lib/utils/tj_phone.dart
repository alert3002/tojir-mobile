/// Префиксы мобильных операторов Таджикистана (9 цифр).
abstract final class TjPhone {
  static const operators = <String, List<String>>{
    'Tcell': ['92', '93', '77', '50', '11'],
    'МегаФон': ['90', '88', '55', '41', '00'],
    'Babilon-M': ['98', '94', '918'],
    'ZET-MOBILE': ['91', '80'],
    'O Mobile': ['20', '78', '17'],
  };

  static final List<String> prefixes = () {
    final seen = <String>{};
    final list = <String>[];
    for (final group in operators.values) {
      for (final p in group) {
        if (seen.add(p)) list.add(p);
      }
    }
    list.sort((a, b) {
      final lc = b.length.compareTo(a.length);
      return lc != 0 ? lc : a.compareTo(b);
    });
    return list;
  }();

  static String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String canonical9(String value) {
    var raw = digitsOnly(value);
    if (raw.startsWith('992') && raw.length >= 12) {
      raw = raw.substring(3, 12);
    } else {
      raw = raw.length > 9 ? raw.substring(0, 9) : raw;
    }
    return raw;
  }

  static bool isValidMobile(String value) {
    final phone = canonical9(value);
    if (phone.length != 9 || !RegExp(r'^\d{9}$').hasMatch(phone)) return false;
    for (final prefix in prefixes) {
      if (phone.startsWith(prefix)) return true;
    }
    return false;
  }

  static String? operatorName(String value) {
    final phone = canonical9(value);
    if (!isValidMobile(phone)) return null;
    for (final entry in operators.entries) {
      final sorted = [...entry.value]..sort((a, b) => b.length.compareTo(a.length));
      for (final prefix in sorted) {
        if (phone.startsWith(prefix)) return entry.key;
      }
    }
    return null;
  }

  static String validationHint() =>
      'Мобильный номер Таджикистана: 9 цифр (92, 90, 77, 78, 00…)';
}
