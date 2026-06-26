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

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ApiClient? _api;
  void Function(String message)? _onError;
  void Function()? _onSuccess;
  int? _pendingTariffId;

  bool get available => isIosApp && !kIsWeb;

  Future<void> init(ApiClient api) async {
    if (!available) return;
    _api = api;
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
    if (api == null) return {};
    final res = await api.get('iap/apple/products/');
    if (res.statusCode != 200) return {};
    final data = jsonDecode(res.body);
    if (data is! Map) return {};
    final products = data['products'];
    if (products is! List) return {};
    final ids = <String>{};
    for (final row in products) {
      if (row is Map) {
        final id = (row['apple_product_id'] ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  Future<Map<String, ProductDetails>> loadProducts(Set<String> ids) async {
    if (!available || ids.isEmpty) return {};
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    return {for (final p in response.productDetails) p.id: p};
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
    _onSuccess = onSuccess;
    _onError = onError;
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
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
    _onSuccess = onSuccess;
    _onError = onError;
    await _iap.restorePurchases();
  }
}
