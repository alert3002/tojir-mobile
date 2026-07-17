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
      _onError?.call(e.toString());
    });
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
    ProductDetailsResponse response;
    try {
      response = await _iap.queryProductDetails(ids);
    } catch (e) {
      throw Exception(_storeKitHint(e.toString()));
    }
    if (response.error != null) {
      throw Exception(_storeKitHint(response.error!.message));
    }
    return {for (final p in response.productDetails) p.id: p};
  }

  static String _storeKitHint(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('failed to get response') ||
        lower.contains('storekit') ||
        lower.contains('platform')) {
      return 'App Store не ответил (StoreKit).\n\n'
          'Проверьте в App Store Connect:\n'
          '1) Consumable IAP: tj.tojir.balance.topup.39 (~\$39.99)\n'
          '2) Подписка: tj.tojir.tariff.standard.monthly\n'
          '3) Paid Apps Agreement подписан\n'
          '4) IAP добавлен к версии приложения и отправлен на review\n'
          '5) Тест на реальном iPhone (не симулятор), интернет включён';
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
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
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
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        _onError?.call(purchase.error?.message ?? 'Ошибка покупки Apple');
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
          _onError?.call(e.toString());
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
