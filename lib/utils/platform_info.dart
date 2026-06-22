import 'package:flutter/foundation.dart';

bool get isIosApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
