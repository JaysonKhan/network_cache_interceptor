
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';
import 'package:network_cache_interceptor/database_helper/database_helper.dart';
import 'dart:io';

void main() {
  late Dio dio;
  late NetworkCacheInterceptor interceptor;
  late MockDatabaseHelper mockDbHelper;

  setUp(() {
    // Initialize the mock database and cache interceptor
    mockDbHelper = MockDatabaseHelper();
    interceptor = NetworkCacheInterceptor(getCachedDataWhenError: true);
    dio = Dio()..interceptors.add(interceptor);
  });

  group('NetworkCacheInterceptor Tests', () {
    test('Should cache response when caching is enabled', () async {
      final options = RequestOptions(path: '/test', extra: {'cache': true});
      final response = Response(
        requestOptions: options,
        statusCode: 200,
        data: {'message': 'Success'},
      );

      // Simulate response handling
      await interceptor.onResponse(response, ResponseInterceptorHandler());

      // Verify that data is stored in the cache
      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData, isNotEmpty);
      expect(cachedData['data'], equals({'message': 'Success'}));
    });

    test('Should return cached data on network error', () async {
      final options = RequestOptions(path: '/test', extra: {'cache': true});

      // Insert mock data into cache
      await mockDbHelper.insertResponse(
        '/test',
        {
          'data': {'message': 'Cached Data'},
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        error: SocketException('No Internet'),
      );

      // Simulate error handling
      await interceptor.onError(error, ErrorInterceptorHandler());

      // Check if cached data is returned instead of throwing an error
      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData['data'], equals({'message': 'Cached Data'}));
    });

    test('Should clear cache database', () async {
      // Insert sample cached data
      await mockDbHelper.insertResponse(
        '/test',
        {
          'data': {'message': 'Cached Data'},
          'timestamp': DateTime.now().toIso8601String()
        },
      );

      // Clear database
      await interceptor.clearDatabase();

      // Ensure the cache is empty
      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData, isEmpty);
    });

    test('Should not cache responses with excluded status codes', () async {
      final options = RequestOptions(path: '/test', extra: {'cache': true});
      final response = Response(
        requestOptions: options,
        statusCode: 401, // Excluded from caching
        data: {'message': 'Unauthorized'},
      );

      await interceptor.onResponse(response, ResponseInterceptorHandler());

      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData, isEmpty); // Should not be cached
    });
  });
}

/// Mock Database Helper for simulating cache storage
class MockDatabaseHelper extends NetworkCacheSQLHelper {
  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Future<void> insertResponse(String key, Map<String, dynamic> value) async {
    _storage[key] = value;
  }

  @override
  Future<Map<String, dynamic>> getResponse(String key) async {
    return _storage[key] ?? {};
  }

  @override
  Future<void> clearDatabase() async {
    _storage.clear();
  }
}
