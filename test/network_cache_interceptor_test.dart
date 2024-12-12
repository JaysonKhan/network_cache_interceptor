import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/database_helper/database_helper.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';
import 'dart:convert';
import 'dart:io';

void main() {
  late Dio dio;
  late NetworkCacheInterceptor interceptor;
  late DatabaseHelper dbHelper;

  setUp(() async {
    // Initialize Dio and add the interceptor
    dio = Dio();
    interceptor = NetworkCacheInterceptor();
    dio.interceptors.add(interceptor);

    // Initialize DatabaseHelper and clear database before each test
    dbHelper = DatabaseHelper();
    await dbHelper.clearDatabase();
  });

  test('Caches response for GET request and retrieves it correctly', () async {
    // Mock endpoint and response
    const testUrl = 'https://mockapi.com/test';
    final mockResponse = {'message': 'Hello, world!'};

    // Intercept Dio requests and provide a mocked response
    dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
      return ResponseBody.fromString(
        jsonEncode(mockResponse),
        200,
        headers: {HttpHeaders.contentTypeHeader: ['application/json']},
      );
    });

    // Make the first request with caching enabled
    final response1 = await dio.get(
      testUrl,
      options: Options(extra: {'cache': true}),
    );

    expect(response1.statusCode, 200);
    expect(response1.data['message'], 'Hello, world!');

    // Simulate a second request (should use cache)
    final response2 = await dio.get(
      testUrl,
      options: Options(extra: {'cache': true}),
    );

    expect(response2.statusCode, 200);
    expect(response2.data['message'], 'Hello, world!');
  });

  test('Does not cache response if caching is disabled', () async {
    // Mock endpoint and response
    const testUrl = 'https://mockapi.com/test';
    final mockResponse = {'message': 'Non-cached response'};

    // Intercept Dio requests and provide a mocked response
    dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
      return ResponseBody.fromString(
        jsonEncode(mockResponse),
        200,
        headers: {HttpHeaders.contentTypeHeader: ['application/json']},
      );
    });

    // Make a request with caching disabled
    final response = await dio.get(
      testUrl,
      options: Options(extra: {'cache': false}),
    );

    expect(response.statusCode, 200);
    expect(response.data['message'], 'Non-cached response');
  });

  test('Respects cache expiration time', () async {
    // Mock endpoint and response
    const testUrl = 'https://mockapi.com/test';
    final mockResponse = {'message': 'Expired response'};

    // Intercept Dio requests and provide a mocked response
    dio.httpClientAdapter = _MockHttpClientAdapter((options) async {
      return ResponseBody.fromString(
        jsonEncode(mockResponse),
        200,
        headers: {HttpHeaders.contentTypeHeader: ['application/json']},
      );
    });

    // Make the first request with caching enabled
    final response1 = await dio.get(
      testUrl,
      options: Options(extra: {'cache': true, 'validate_time': 1}), // Cache valid for 1 minute
    );

    expect(response1.statusCode, 200);
    expect(response1.data['message'], 'Expired response');

    // Simulate cache expiration
    await Future.delayed(Duration(minutes: 2));

    // Make another request (should not use cache)
    final response2 = await dio.get(
      testUrl,
      options: Options(extra: {'cache': true, 'validate_time': 1}),
    );

    expect(response2.statusCode, 200);
    expect(response2.data['message'], 'Expired response');
  });
}

class _MockHttpClientAdapter extends HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) onRequest;

  _MockHttpClientAdapter(this.onRequest);

  @override
  Future<HttpClientRequest> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final response = await onRequest(options);
    final mockStream = Stream<List<int>>.fromIterable([response.bytes]);
    final responseHeaders = response.headers.map((key, values) => MapEntry(key, values.join(", ")));

    return MockHttpClientRequest(mockStream, response.statusCode, responseHeaders);
  }

  @override
  void close({bool force = false}) {}
}

class MockHttpClientRequest implements HttpClientRequest {
  final Stream<List<int>> _stream;
  final int _statusCode;
  final Map<String, String> _headers;

  MockHttpClientRequest(this._stream, this._statusCode, this._headers);

  @override
  Stream<List<int>> get responseStream => _stream;

  @override
  int get statusCode => _statusCode;

  @override
  Map<String, String> get headers => _headers;

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
