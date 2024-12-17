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
    mockDbHelper = MockDatabaseHelper();
    interceptor = NetworkCacheInterceptor();
    dio = Dio()..interceptors.add(interceptor);
  });

  group('NetworkCacheInterceptor Tests', () {
    test('Should cache response when caching is enabled', () async {
      final options = Options(extra: {'cache': true});
      final response = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {'message': 'Success'},
      );

      await interceptor.onResponse(response, ResponseInterceptorHandler());

      expect(await mockDbHelper.getResponse('/test'), isNotEmpty);
    });

    test('Should return cached data on network error', () async {
      final options = RequestOptions(path: '/test', extra: {'cache': true});
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

      interceptor.onError(error, ErrorInterceptorHandler());

      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData['data'], equals({'message': 'Cached Data'}));
    });

    test('Should clear cache database', () async {
      await mockDbHelper.insertResponse(
        '/test',
        {
          'data': {'message': 'Cached Data'},
          'timestamp': DateTime.now().toIso8601String()
        },
      );

      await interceptor.clearDatabase();
      final cachedData = await mockDbHelper.getResponse('/test');
      expect(cachedData, isEmpty);
    });
  });
}

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
