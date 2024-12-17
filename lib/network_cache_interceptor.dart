import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/database_helper/database_helper.dart';

/// Dio interceptor to handle network caching
class NetworkCacheInterceptor extends Interceptor {
  static final NetworkCacheInterceptor _instance = NetworkCacheInterceptor._internal();
  final NetworkCacheSQLHelper _dbHelper = NetworkCacheSQLHelper();

  List<int> _defaultNoCacheStatusCodes;
  int _defaultCacheValidity;
  bool _getCachedDataWhenError;

  factory NetworkCacheInterceptor({
    List<int> noCacheStatusCodes = const [401, 403],
    int cacheValidityMinutes = 30,
    bool getCachedDataWhenError = true,
  }) {
    _instance._defaultNoCacheStatusCodes = noCacheStatusCodes;
    _instance._defaultCacheValidity = cacheValidityMinutes;
    _instance._getCachedDataWhenError = getCachedDataWhenError;
    return _instance;
  }

  NetworkCacheInterceptor._internal()
      : _defaultNoCacheStatusCodes = [401, 403],
        _defaultCacheValidity = 30,
        _getCachedDataWhenError = true;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final bool isCache = options.extra['cache'] ?? false;
    final int cacheValidity = options.extra['validate_time'] ?? _defaultCacheValidity;

    if (!isCache) {
      handler.next(options);
      return;
    }

    try {
      final cacheKey = '${options.baseUrl}${options.path}?${options.queryParameters.toString()}';
      final cachedResponse = await _dbHelper.getResponse(cacheKey);

      if (cachedResponse.isNotEmpty) {
        final cachedTimestamp = DateTime.tryParse(cachedResponse['timestamp'] ?? '') ?? DateTime(1970);
        final specifiedCacheDate =
            options.extra['cache_updated_date'] != null ? DateTime.tryParse(options.extra['cache_updated_date']) : null;

        if (specifiedCacheDate != null && cachedTimestamp.isBefore(specifiedCacheDate) ||
            DateTime.now().difference(cachedTimestamp).inMinutes < cacheValidity) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: cachedResponse['data'],
              statusCode: 200,
            ),
          );
          return;
        }
      }
    } catch (e) {
      log('Error during cache check: $e');
    }

    handler.next(options);
  }

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    final bool isCache = response.requestOptions.extra['cache'] ?? false;

    if (isCache &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! <= 300 &&
        response.data != null &&
        !_defaultNoCacheStatusCodes.contains(response.statusCode)) {
      final cacheKey =
          '${response.requestOptions.baseUrl}${response.requestOptions.path}?${response.requestOptions.queryParameters.toString()}';
      final responseToCache = {
        'data': response.data,
        'timestamp': DateTime.now().toIso8601String(),
      };

      try {
        await _dbHelper.insertResponse(cacheKey, responseToCache);
      } catch (e) {
        log('Error during cache insert: $e');
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    log('Dio Error: ${err.message}');
    if (!_getCachedDataWhenError) {
      handler.next(err);
      return;
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.unknown && err.error is SocketException) {
      final cacheKey =
          '${err.requestOptions.baseUrl}${err.requestOptions.path}?${err.requestOptions.queryParameters.toString()}';
      try {
        final cachedResponse = await _dbHelper.getResponse(cacheKey);
        if (cachedResponse.isNotEmpty) {
          handler.resolve(
            Response(
              requestOptions: err.requestOptions,
              data: cachedResponse['data'],
              statusCode: 200,
            ),
          );
          return;
        }
      } catch (e) {
        log('Error fetching from cache: $e');
      }
    }

    handler.next(err);
  }

  Future<void> clearDatabase() async {
    try {
      await _dbHelper.clearDatabase();
      log('Database cleared successfully');
    } catch (e) {
      log('Error clearing database: $e');
    }
  }
}
