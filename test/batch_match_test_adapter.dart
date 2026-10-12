import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class BatchMatchTestAdapter implements HttpClientAdapter {
  final Map<String, dynamic>? payload;
  final bool timeout;
  RequestOptions? lastRequest;

  BatchMatchTestAdapter({this.payload, this.timeout = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(payload ?? const {'code': 0, 'data': {}}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
