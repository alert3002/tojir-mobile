import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'app.dart';
import 'utils/platform_info.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The backend validates the classic App Store receipt through verifyReceipt.
  // Configure StoreKit 1 before InAppPurchase.instance registers its platform.
  if (isIosApp) {
    await InAppPurchaseStoreKitPlatform.enableStoreKit1();
  }
  runApp(const ProviderScope(child: TojirApp()));
}
