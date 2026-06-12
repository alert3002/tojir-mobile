import 'dart:convert';

/// Зеркало web `productScanUtils.js` — нормализация QR/штрихкода и поиск товара.
String normalizeScanCode(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';

  if (text.startsWith('{')) {
    try {
      final obj = (const JsonDecoder()).convert(text);
      if (obj is Map) {
        final pick = obj['imei'] ?? obj['IMEI'] ?? obj['barcode'] ?? obj['sku'] ?? obj['code'] ?? obj['id'];
        if (pick != null) return pick.toString().trim();
      }
    } catch (_) {
      // not JSON
    }
  }

  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
    try {
      final uri = Uri.parse(text);
      final fromQuery = uri.queryParameters['imei'] ??
          uri.queryParameters['IMEI'] ??
          uri.queryParameters['barcode'] ??
          uri.queryParameters['sku'] ??
          uri.queryParameters['code'];
      if (fromQuery != null && fromQuery.trim().isNotEmpty) return fromQuery.trim();
      final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last.trim();
    } catch (_) {
      // invalid URL
    }
  }

  return text;
}

List<dynamic> _scanFieldValues(Map<String, dynamic> product) {
  return [
    product['barcode'],
    product['sku'],
    product['id'],
    product['product_id'],
    product['name'],
    product['product_name'],
    product['model'],
  ];
}

Map<String, dynamic>? findOutletProductByCode(String code, List<Map<String, dynamic>> outletProducts) {
  final q = normalizeScanCode(code).toLowerCase();
  if (q.isEmpty) return null;

  for (final p in outletProducts) {
    for (final field in [p['barcode'], p['sku']]) {
      if (field != null && field.toString().trim().toLowerCase() == q) return p;
    }
  }

  for (final p in outletProducts) {
    for (final v in _scanFieldValues(p)) {
      if (v != null && v.toString().trim().toLowerCase().contains(q)) return p;
    }
  }

  return null;
}

Map<String, dynamic>? findWarehouseProductByCode(String code, List<Map<String, dynamic>> products) {
  final q = normalizeScanCode(code).toLowerCase();
  if (q.isEmpty) return null;

  for (final p in products) {
    for (final field in [p['barcode'], p['sku']]) {
      if (field != null && field.toString().trim().toLowerCase() == q) return p;
    }
  }

  for (final p in products) {
    for (final v in _scanFieldValues(p)) {
      if (v != null && v.toString().trim().toLowerCase().contains(q)) return p;
    }
  }

  return null;
}

String warehouseProductOptionLabel(Map<String, dynamic> p) {
  final name = (p['product_name'] ?? p['name'] ?? '').toString();
  final model = (p['model'] ?? '').toString().trim();
  final base = '$name${model.isEmpty ? '' : ' $model'} — ${p['sku'] ?? ''}';
  final barcode = (p['barcode'] ?? '').toString().trim();
  return barcode.isEmpty ? base : '$base · $barcode';
}
