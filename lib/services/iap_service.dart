import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/api_client.dart';
import '../utils/platform_info.dart';

/// Apple In-App Purchase (только iOS).
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  /// Должен совпадать с App Store Connect + `APPLE_IAP_BALANCE_PRODUCT_ID` на сервере.
  static const defaultBalanceProductId = 'tj.tojir.balance.topup.39';
  static const defaultBalanceCreditTjs = 350.0;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ApiClient? _api;
  void Function(String message)? _onError;
  void Function()? _onSuccess;
  int? _pendingTariffId;
  bool _pendingBalance = false;

  bool get available => isIosApp && !kIsWeb;

  Future<void> init(ApiClient api) async {
    _api = api;
    if (!available) return;
    final ok = await _iap.isAvailable();
    if (!ok) return;
    _sub ??= _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (Object e) {
      _onError?.call(formatStoreKitError(e));
    });
  }

  /// Never show raw "SKErrorDomain" to users / App Review.
  static String formatStoreKitError(Object? error, {String? code, String? message}) {
    final rawCode = (code ?? (error is IAPError ? error.code : '')).toString().trim();
    final rawMsg = (message ?? (error is IAPError ? error.message : error?.toString() ?? ''))
        .toString()
        .trim();
    final lower = '$rawCode $rawMsg'.toLowerCase();

    if (lower.contains('cancel') || rawCode == '2' || lower.contains('paymentcancelled')) {
      return ''; // caller treats empty as silent cancel
    }
    if (rawCode == '5' || lower.contains('storeproductnotavailable') || lower.contains('not available')) {
      return 'Этот продукт сейчас недоступен в App Store. Повторите позже.';
    }
    if (rawCode == '4' || lower.contains('paymentnotallowed')) {
      return 'Покупки в App Store запрещены на этом устройстве (ограничения / Screen Time).';
    }
    if (rawCode == '3' || lower.contains('paymentinvalid')) {
      return 'Не удалось оформить оплату App Store. Повторите попытку.';
    }
    if (rawMsg.isNotEmpty &&
        !rawMsg.toLowerCase().contains('skerrordomain') &&
        rawMsg.toLowerCase() != 'unknown') {
      return rawMsg;
    }
    return 'Не удалось завершить оплату App Store. Закройте приложение и повторите через минуту.';
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<Set<String>> productIdsFromApi() async {
    final api = _api;
    if (api == null) return {defaultBalanceProductId};
    final res = await api.get('iap/apple/products/');
    if (res.statusCode != 200) return {defaultBalanceProductId};
    final data = jsonDecode(res.body);
    if (data is! Map) return {defaultBalanceProductId};
    final products = data['products'];
    if (products is! List) return {defaultBalanceProductId};
    final ids = <String>{};
    for (final row in products) {
      if (row is Map) {
        final id = (row['apple_product_id'] ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    ids.add(defaultBalanceProductId);
    return ids;
  }

  /// Balance top-up consumable: из API или дефолт (если прод ещё не задеплоен).
  Future<({String productId, double creditTjs})> balanceTopupInfoFromApi() async {
    final api = _api;
    if (api != null) {
      try {
        final res = await api.get('iap/apple/products/');
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final products = data['products'];
            if (products is List) {
              for (final row in products) {
                if (row is! Map) continue;
                if ((row['kind'] ?? '').toString() != 'balance_topup') continue;
                final id = (row['apple_product_id'] ?? '').toString().trim();
                if (id.isEmpty) continue;
                final credit = double.tryParse(row['credit_tjs']?.toString() ?? '') ?? defaultBalanceCreditTjs;
                return (productId: id, creditTjs: credit);
              }
            }
          }
        }
      } catch (_) {
        // fallback below
      }
    }
    return (productId: defaultBalanceProductId, creditTjs: defaultBalanceCreditTjs);
  }

  Future<Map<String, ProductDetails>> loadProducts(Set<String> ids) async {
    if (!available || ids.isEmpty) return {};
    if (!await _iap.isAvailable()) {
      throw Exception('App Store временно недоступен. Повторите попытку через минуту.');
    }

    Object? lastError;
    Set<String> lastMissing = {};
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final response = await _iap.queryProductDetails(ids);
        if (response.error != null) {
          lastError = response.error!.message;
        } else {
          final found = {for (final p in response.productDetails) p.id: p};
          lastMissing = ids.difference(found.keys.toSet());
          // StoreKit may return success with empty list when IAP isn't ready in ASC.
          if (found.isNotEmpty && lastMissing.isEmpty) return found;
          if (found.isNotEmpty) return found;
          lastError = 'products_not_found';
        }
      } catch (e) {
        lastError = e;
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 900 * (attempt + 1)));
      }
    }
    if (lastMissing.isNotEmpty || lastError?.toString() == 'products_not_found') {
      throw Exception(
        'Продукт App Store не загрузился (${ids.join(', ')}). '
        'Проверьте Paid Apps Agreement и статус IAP в App Store Connect.',
      );
    }
    throw Exception(_storeKitHint(lastError?.toString() ?? 'StoreKit error'));
  }

  static String _storeKitHint(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('failed to get response') ||
        lower.contains('storekit') ||
        lower.contains('platform')) {
      return 'Не удалось связаться с App Store. Проверьте интернет и повторите попытку через минуту.';
    }
    return raw;
  }

  Future<void> purchaseSubscription({
    required ProductDetails product,
    required int tariffId,
    void Function()? onSuccess,
    void Function(String message)? onError,
  }) async {
    if (!available) {
      onError?.call('IAP только на iPhone/iPad');
      return;
    }
    _pendingTariffId = tariffId;
    _pendingBalance = false;
    _onSuccess = onSuccess;
    _onError = onError;
    try {
      final param = PurchaseParam(productDetails: product);
      final ok = await _iap.buyNonConsumable(purchaseParam: param);
      if (!ok) {
        onError?.call('Не удалось открыть оплату App Store. Повторите попытку.');
      }
    } catch (e) {
      onError?.call(formatStoreKitError(e));
    }
  }

  Future<void> purchaseBalanceTopup({
    required ProductDetails product,
    void Function()? onSuccess,
    void Function(String message)? onError,
  }) async {
    if (!available) {
      onError?.call('IAP только на iPhone/iPad');
      return;
    }
    _pendingTariffId = null;
    _pendingBalance = true;
    _onSuccess = onSuccess;
    _onError = onError;
    try {
      final param = PurchaseParam(productDetails: product);
      final ok = await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
      if (!ok) {
        onError?.call('Не удалось открыть оплату App Store. Повторите попытку.');
      }
    } catch (e) {
      onError?.call(formatStoreKitError(e));
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.canceled) {
        _onError?.call('');
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        final err = purchase.error;
        final msg = formatStoreKitError(
          err,
          code: err?.code,
          message: err?.message,
        );
        _onError?.call(msg);
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        try {
          await _verifyOnServer(purchase);
          _onSuccess?.call();
        } catch (e) {
          _onError?.call(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim());
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyOnServer(PurchaseDetails purchase) async {
    final api = _api;
    if (api == null) throw Exception('API не инициализирован');

    final receipt = purchase.verificationData.serverVerificationData;
    if (receipt.isEmpty) {
      throw Exception('Пустой чек Apple');
    }

    final body = <String, dynamic>{
      'product_id': purchase.productID,
      'receipt_data': receipt,
      'transaction_id': purchase.purchaseID,
    };
    if (_pendingBalance) {
      final res = await api.post('iap/apple/verify-balance/', body: body);
      final data = jsonDecode(res.body);
      if (res.statusCode == 404) {
        throw Exception(
          'На сервере нет endpoint verify-balance. '
          'Задеплойте backend на api.tojir.tj и добавьте APPLE_IAP_BALANCE_PRODUCT_ID.',
        );
      }
      if (res.statusCode != 200) {
        final detail = data is Map ? (data['detail'] ?? 'Ошибка сервера') : 'Ошибка сервера';
        throw Exception(detail.toString());
      }
      return;
    }

    if (_pendingTariffId != null) {
      body['tariff_id'] = _pendingTariffId;
    }

    final res = await api.post('iap/apple/verify/', body: body);
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      final detail = data is Map ? (data['detail'] ?? 'Ошибка сервера') : 'Ошибка сервера';
      throw Exception(detail.toString());
    }
  }

  Future<void> restorePurchases({
    void Function()? onSuccess,
    void Function(String message)? onError,
  }) async {
    if (!available) return;
    _pendingBalance = false;
    _onSuccess = onSuccess;
    _onError = onError;
    await _iap.restorePurchases();
  }
}
