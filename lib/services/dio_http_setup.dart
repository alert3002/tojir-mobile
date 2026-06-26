import 'package:dio/dio.dart';

import 'dio_http_setup_stub.dart'
    if (dart.library.io) 'dio_http_setup_io.dart' as impl;

void configureDioHttpClient(Dio dio) => impl.configureDioHttpClient(dio);

bool isSocketLikeError(Object? error) => impl.isSocketLikeError(error);
