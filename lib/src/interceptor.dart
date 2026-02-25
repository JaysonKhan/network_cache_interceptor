import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/src/aes_helper/aes_helper.dart';
import 'package:network_cache_interceptor/src/database_helper/database_helper.dart';

/// A Dio interceptor for caching network requests.
/// This interceptor enables caching of responses to optimize network calls.
///
/// Supports optional AES-GCM encryption for both cache keys and response data.
/// When [encryptionKey] is provided, all data is encrypted before being stored
/// in the local database, and decrypted when read back.
class NetworkCacheInterceptor extends Interceptor {
  static final NetworkCacheInterceptor _instance = NetworkCacheInterceptor._internal();
  final NetworkCacheSQLHelper _dbHelper = NetworkCacheSQLHelper();

  List<int> _defaultNoCacheStatusCodes;
  Set<String> _defaultNoCacheHttpMethods;
  int _defaultCacheValidity;
  bool _getCachedDataWhenError;
  bool _uniqueWithHeader;
  AESHelper? _aesHelper;

  /// Creates a new instance of [NetworkCacheInterceptor] with customizable options.
  ///
  /// - `noCacheStatusCodes`: List of status codes that should not be cached.
  /// - `cacheValidityMinutes`: Defines cache expiration duration in minutes.
  /// - `getCachedDataWhenError`: If true, cached data is returned on network failure.
  /// - `uniqueWithHeader`: Differentiates cache keys based on request headers.
  /// - `noCacheHttpMethods`: List of http methods (e.g. `POST`, `PUT`, `GET`, etc.)
  ///                         which should be not be cached. Those values will be converted
  ///                         to lowerCase values, e.G. `POST` will become `post`.
  /// - `encryptionKey`: Optional AES encryption key (1-32 characters).
  ///                    When provided, all cache keys and response data will be
  ///                    encrypted using AES-GCM before being stored.
  factory NetworkCacheInterceptor({
    List<int> noCacheStatusCodes = const [401, 403, 304],
    List<String> noCacheHttpMethods = const ['POST'],
    int cacheValidityMinutes = 30,
    bool getCachedDataWhenError = true,
    bool uniqueWithHeader = false,
    String? encryptionKey,
  }) {
    assert(
      encryptionKey == null || (encryptionKey.isNotEmpty && encryptionKey.length <= 32),
      'Encryption key must be between 1 and 32 characters',
    );

    _instance._defaultNoCacheStatusCodes = noCacheStatusCodes;
    _instance._defaultCacheValidity = cacheValidityMinutes;
    _instance._getCachedDataWhenError = getCachedDataWhenError;
    _instance._uniqueWithHeader = uniqueWithHeader;
    _instance._defaultNoCacheHttpMethods = noCacheHttpMethods.map((e) => e.toLowerCase()).toSet();
    _instance._aesHelper = encryptionKey != null ? AESHelper(encryptionKey) : null;
    return _instance;
  }

  NetworkCacheInterceptor._internal()
      : _defaultNoCacheStatusCodes = const [401, 403, 304],
        _defaultNoCacheHttpMethods = const {'post'},
        _defaultCacheValidity = 30,
        _getCachedDataWhenError = true,
        _uniqueWithHeader = false,
        _aesHelper = null;

  /// Encrypts the cache key if encryption is enabled.
  /// Uses deterministic AES encryption (fixed IV) so the same cache key
  /// always produces the same encrypted output — required for DB lookups.
  String _encryptCacheKey(String cacheKey) {
    if (_aesHelper == null) return cacheKey;
    return _aesHelper!.encryptDeterministic(cacheKey);
  }

  /// Encrypts response data as JSON string if encryption is enabled.
  String _encryptData(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    if (_aesHelper == null) return jsonString;
    return _aesHelper!.encrypt(jsonString);
  }

  /// Decrypts response data string and returns parsed JSON map.
  /// If encryption is disabled, parses the string directly.
  Map<String, dynamic> _decryptData(String encryptedData) {
    if (_aesHelper == null) return jsonDecode(encryptedData);
    final decrypted = _aesHelper!.decrypt(encryptedData);
    return jsonDecode(decrypted);
  }

  /// Builds and returns the cache key for a given request options.
  String _buildCacheKey(RequestOptions options) {
    final String uniqueKey = options.extra['unique_key'] ?? '';
    Map<String, dynamic> filteredHeaders = Map.from(options.headers);
    filteredHeaders.remove('Authorization');
    filteredHeaders.remove('User-Agent');
    filteredHeaders.remove('content-length');
    filteredHeaders.remove('X-SESSION-ID');

    String cacheKey = '${options.baseUrl}${options.path}?${jsonEncode(options.queryParameters)}';

    if (uniqueKey.isNotEmpty) {
      cacheKey += uniqueKey;
    }
    if (_uniqueWithHeader) {
      cacheKey += jsonEncode(filteredHeaders);
    }
    return cacheKey;
  }

  /// Intercepts outgoing requests and checks for cached responses.
  /// If caching is enabled and valid data exists, the cached response is returned.
  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final dynamic cacheMode = options.extra['cache'] ?? false;
    final bool isCache = cacheMode == true || cacheMode == 'only_cache';
    final bool isOnlyCache = cacheMode == 'only_cache';
    final bool isIgnoredHttpMethod = _defaultNoCacheHttpMethods.contains(options.method.toLowerCase());
    final int cacheValidity = options.extra['validate_time'] ?? _defaultCacheValidity;

    if (!isCache) {
      handler.next(options);
      return;
    }

    if (isIgnoredHttpMethod) {
      handler.next(options);
      return;
    }

    try {
      final cacheKey = _buildCacheKey(options);
      final encryptedKey = _encryptCacheKey(cacheKey);
      final cachedResponse = await _dbHelper.getResponse(encryptedKey);

      if (cachedResponse.isNotEmpty) {
        final responseString = cachedResponse['response'] as String? ?? '';
        final cachedData = _decryptData(responseString);

        final cachedTimestamp = DateTime.tryParse(cachedData['timestamp'] ?? '') ?? DateTime(1970);
        final specifiedCacheDate =
            options.extra['cache_updated_date'] != null ? DateTime.tryParse(options.extra['cache_updated_date']) : null;

        if ((specifiedCacheDate != null && cachedTimestamp.isBefore(specifiedCacheDate)) ||
            DateTime.now().difference(cachedTimestamp).inMinutes < cacheValidity) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: cachedData['data'],
              statusCode: 200,
            ),
          );
          return;
        }
      }

      // only_cache mode: no cached data found → reject without network request
      if (isOnlyCache) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'no_cache_available',
          ),
        );
        return;
      }
    } catch (e, stackTrace) {
      log('Error fetching from cache: $e', stackTrace: stackTrace);

      // only_cache mode: error during cache lookup → reject
      if (isOnlyCache) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'no_cache_available',
          ),
        );
        return;
      }
    }

    handler.next(options);
  }

  /// Handles successful responses and caches them for future requests.
  /// Only `GET` responses with valid status codes are cached.
  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    final data = response.data;

    if (data is! Map<String, dynamic>) {
      handler.next(response);
      return;
    }

    if (data['success'] != true) {
      handler.next(response);
      return;
    }

    if (!_defaultNoCacheStatusCodes.contains(response.statusCode) &&
        !_defaultNoCacheHttpMethods.contains(response.requestOptions.method.toLowerCase())) {
      final cacheKey = _buildCacheKey(response.requestOptions);
      final encryptedKey = _encryptCacheKey(cacheKey);

      final responseToCache = {
        'data': response.data,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final encryptedData = _encryptData(responseToCache);

      try {
        await _dbHelper.insertResponse(encryptedKey, encryptedData);
      } catch (e) {
        log('Error during cache insert: $e');
      }
    }

    handler.next(response);
  }

  /// Handles request errors and attempts to return cached data if enabled.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_getCachedDataWhenError) {
      handler.next(err);
      return;
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.type == DioExceptionType.unknown && err.error is SocketException)) {
      final cacheKey = _buildCacheKey(err.requestOptions);
      final encryptedKey = _encryptCacheKey(cacheKey);

      try {
        final cachedResponse = await _dbHelper.getResponse(encryptedKey);
        if (cachedResponse.isNotEmpty) {
          final responseString = cachedResponse['response'] as String? ?? '';
          final cachedData = _decryptData(responseString);

          handler.resolve(
            Response(
              requestOptions: err.requestOptions,
              data: cachedData['data'],
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
