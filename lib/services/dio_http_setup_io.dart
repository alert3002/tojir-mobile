import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

void configureDioHttpClient(Dio dio) {
  final adapter = IOHttpClientAdapter();
  adapter.createHttpClient = () {
    final client = HttpClient();
    client.idleTimeout = const Duration(seconds: 15);
    return client;
  };
  dio.httpClientAdapter = adapter;
}

bool isSocketLikeError(Object? error) =>
    error is SocketException || error is HttpException;
