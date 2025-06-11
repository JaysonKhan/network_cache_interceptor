import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/database_helper/database_helper.dart';

/// A Dio interceptor for caching network requests.
/// This interceptor enables caching of responses to optimize network calls.
class NetworkCacheInterceptor extends Interceptor {
  static final NetworkCacheInterceptor _instance =
      NetworkCacheInterceptor._internal();
  final NetworkCacheSQLHelper _dbHelper = NetworkCacheSQLHelper();

  List<int> _defaultNoCacheStatusCodes;
  int _defaultCacheValidity;
  bool _getCachedDataWhenError;
  bool _uniqueWithHeader;

  /// Creates a new instance of [NetworkCacheInterceptor] with customizable options.
  ///
  /// - `noCacheStatusCodes`: List of status codes that should not be cached.
  /// - `cacheValidityMinutes`: Defines cache expiration duration in minutes.
  /// - `getCachedDataWhenError`: If true, cached data is returned on network failure.
  /// - `uniqueWithHeader`: Differentiates cache keys based on request headers.
  factory NetworkCacheInterceptor({
    List<int> noCacheStatusCodes = const [401, 403, 304],
    int cacheValidityMinutes = 30,
    bool getCachedDataWhenError = true,
    bool uniqueWithHeader = false,
  }) {
    _instance._defaultNoCacheStatusCodes = noCacheStatusCodes;
    _instance._defaultCacheValidity = cacheValidityMinutes;
    _instance._getCachedDataWhenError = getCachedDataWhenError;
    _instance._uniqueWithHeader = uniqueWithHeader;
    return _instance;
  }

  NetworkCacheInterceptor._internal()
      : _defaultNoCacheStatusCodes = [401, 403, 304],
        _defaultCacheValidity = 30,
        _getCachedDataWhenError = true,
        _uniqueWithHeader = false;

  /// Intercepts outgoing requests and checks for cached responses.
  /// If caching is enabled and valid data exists, the cached response is returned.
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final bool isCache = options.extra['cache'] ?? false;
    final String uniqueKey = options.extra['unique_key'] ?? '';
    final int cacheValidity =
        options.extra['validate_time'] ?? _defaultCacheValidity;
    Map<String, dynamic> filteredHeaders = Map.from(options.headers);
    filteredHeaders.remove('Authorization'); // Ignore access tokens
    filteredHeaders.remove('User-Agent'); // Ignore user agents

    if (!isCache) {
      handler.next(options);
      return;
    }

    try {
      String cacheKey =
          '${options.baseUrl}${options.path}?${jsonEncode(options.queryParameters)}';

      if (uniqueKey.isNotEmpty) {
        cacheKey += uniqueKey;
      }
      if (_uniqueWithHeader) {
        cacheKey += jsonEncode(filteredHeaders);
      }
      final cachedResponse = await _dbHelper.getResponse(cacheKey);

      if (cachedResponse.isNotEmpty) {
        final cachedTimestamp =
            DateTime.tryParse(cachedResponse['timestamp'] ?? '') ??
                DateTime(1970);
        final specifiedCacheDate = options.extra['cache_updated_date'] != null
            ? DateTime.tryParse(options.extra['cache_updated_date'])
            : null;

        if (specifiedCacheDate != null &&
                cachedTimestamp.isBefore(specifiedCacheDate) ||
            DateTime.now().difference(cachedTimestamp).inMinutes <
                cacheValidity) {
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
    } catch (e, stackTrace) {
      log('Error fetching from cache: $e', stackTrace: stackTrace);
    }

    handler.next(options);
  }

  /// Handles successful responses and caches them for future requests.
  /// Only `GET` responses with valid status codes are cached.
  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    if (response.requestOptions.method == 'GET' &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! <= 300 &&
        response.data != null &&
        !_defaultNoCacheStatusCodes.contains(response.statusCode)) {
      final String uniqueKey =
          response.requestOptions.extra['unique_key'] ?? '';
      Map<String, dynamic> filteredHeaders =
          Map.from(response.requestOptions.headers);
      filteredHeaders.remove('Authorization'); // Ignore access tokens
      filteredHeaders.remove('User-Agent'); // Ignore user agents
      String cacheKey =
          '${response.requestOptions.baseUrl}${response.requestOptions.path}?${jsonEncode(response.requestOptions.queryParameters)}';

      if (uniqueKey.isNotEmpty) {
        cacheKey += uniqueKey;
      }
      if (_uniqueWithHeader) {
        cacheKey += jsonEncode(filteredHeaders);
      }
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

  /// Handles request errors and attempts to return cached data if enabled.
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
        err.type == DioExceptionType.connectionError ||
        (err.type == DioExceptionType.unknown &&
            err.error is SocketException)) {
      final uniqueKey = err.requestOptions.extra['unique_key'] ?? '';
      Map<String, dynamic> filteredHeaders =
          Map.from(err.requestOptions.headers);
      filteredHeaders.remove('Authorization'); // Ignore access tokens
      filteredHeaders.remove('User-Agent'); // Ignore user agents
      String cacheKey =
          '${err.requestOptions.baseUrl}${err.requestOptions.path}?${jsonEncode(err.requestOptions.queryParameters)}';

      if (uniqueKey.isNotEmpty) {
        cacheKey += uniqueKey;
      }
      if (_uniqueWithHeader) {
        cacheKey += jsonEncode(filteredHeaders);
      }
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
      } catch (e, stackTrace) {
        log('Error fetching from cache: $e', stackTrace: stackTrace);
      }
    }

    handler.next(err);
  }

  /// Clears all cached responses from the local database.
  Future<void> clearDatabase() async {
    try {
      await _dbHelper.clearDatabase();
      log('Database cleared successfully');
    } catch (e) {
      log('Error clearing database: $e');
    }
  }
}
