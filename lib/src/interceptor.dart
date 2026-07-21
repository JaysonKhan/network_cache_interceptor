import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/src/aes_helper/aes_helper.dart';
import 'package:network_cache_interceptor/src/database_helper/database_helper.dart';

/// Signature for a callback that decides whether a successful [Response]
/// should be cached. Return `true` to cache the response, `false` to skip it.
///
/// This runs in addition to the built-in checks (status code range and
/// no-cache HTTP methods), so it can only further restrict what gets cached.
typedef CacheWhenPredicate = bool Function(Response response);

/// A Dio interceptor for caching network requests.
///
/// This interceptor stores successful responses in a local SQLite database and
/// serves them back when caching is requested or when the network is
/// unavailable, improving perceived performance and enabling offline access.
///
/// Optional encryption is supported. When [NetworkCacheInterceptor.new] is given
/// an `encryptionKey`, response bodies are encrypted with AES-GCM (using a random
/// IV per entry) and cache keys are encrypted deterministically with AES-CBC (a
/// fixed IV derived from the key) so that lookups stay consistent.
class NetworkCacheInterceptor extends Interceptor {
  static final NetworkCacheInterceptor _instance =
      NetworkCacheInterceptor._internal();
  final NetworkCacheSQLHelper _dbHelper = NetworkCacheSQLHelper();

  List<int> _defaultNoCacheStatusCodes;
  Set<String> _defaultNoCacheHttpMethods;
  int _defaultCacheValidity;
  bool _getCachedDataWhenError;
  bool _uniqueWithHeader;
  AESHelper? _aesHelper;
  CacheWhenPredicate? _cacheWhen;

  /// Creates a new instance of [NetworkCacheInterceptor] with customizable options.
  ///
  /// - [noCacheStatusCodes]: List of status codes that should not be cached.
  /// - [cacheValidityMinutes]: Defines cache expiration duration in minutes.
  /// - [getCachedDataWhenError]: If true, cached data is returned on network failure.
  /// - [uniqueWithHeader]: Differentiates cache keys based on request headers.
  /// - [noCacheHttpMethods]: List of HTTP methods (e.g. `POST`, `PUT`) that should
  ///   not be cached. Values are compared case-insensitively.
  /// - [cacheWhen]: Optional predicate to further restrict which successful
  ///   responses are cached. When `null` (the default), every response that
  ///   passes the built-in checks is cached. For example, an API that wraps its
  ///   payload in `{ "success": true, ... }` can opt in with
  ///   `cacheWhen: (r) => r.data is Map && r.data['success'] == true`.
  /// - [encryptionKey]: Optional AES encryption key (1-32 characters). When
  ///   provided, cache keys and response data are encrypted before being stored.
  factory NetworkCacheInterceptor({
    List<int> noCacheStatusCodes = const [401, 403, 304],
    List<String> noCacheHttpMethods = const ['POST'],
    int cacheValidityMinutes = 30,
    bool getCachedDataWhenError = true,
    bool uniqueWithHeader = false,
    CacheWhenPredicate? cacheWhen,
    String? encryptionKey,
  }) {
    assert(
      encryptionKey == null ||
          (encryptionKey.isNotEmpty && encryptionKey.length <= 32),
      'Encryption key must be between 1 and 32 characters',
    );

    _instance._defaultNoCacheStatusCodes = noCacheStatusCodes;
    _instance._defaultCacheValidity = cacheValidityMinutes;
    _instance._getCachedDataWhenError = getCachedDataWhenError;
    _instance._uniqueWithHeader = uniqueWithHeader;
    _instance._defaultNoCacheHttpMethods =
        noCacheHttpMethods.map((e) => e.toLowerCase()).toSet();
    _instance._cacheWhen = cacheWhen;
    _instance._aesHelper =
        encryptionKey != null ? AESHelper(encryptionKey) : null;
    return _instance;
  }

  NetworkCacheInterceptor._internal()
      : _defaultNoCacheStatusCodes = const [401, 403, 304],
        _defaultNoCacheHttpMethods = const {'post'},
        _defaultCacheValidity = 30,
        _getCachedDataWhenError = true,
        _uniqueWithHeader = false,
        _cacheWhen = null,
        _aesHelper = null;

  /// Encrypts the cache key if encryption is enabled.
  ///
  /// Uses deterministic AES-CBC (fixed IV) so the same cache key always produces
  /// the same encrypted output — required for consistent database lookups.
  String _encryptCacheKey(String cacheKey) {
    if (_aesHelper == null) return cacheKey;
    return _aesHelper!.encryptDeterministic(cacheKey);
  }

  /// Serializes [data] to a JSON string, encrypting it with AES-GCM when
  /// encryption is enabled.
  String _encryptData(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    if (_aesHelper == null) return jsonString;
    return _aesHelper!.encrypt(jsonString);
  }

  /// Decrypts (if needed) and decodes a stored payload back into a JSON map.
  Map<String, dynamic> _decryptData(String storedData) {
    final jsonString =
        _aesHelper == null ? storedData : _aesHelper!.decrypt(storedData);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// Builds the cache key for a given request.
  ///
  /// The key is composed of the URL and query parameters, optionally extended
  /// with `unique_key` from `options.extra` and, when [uniqueWithHeader] is set,
  /// the request headers (excluding volatile/sensitive ones).
  String _buildCacheKey(RequestOptions options) {
    final String uniqueKey = options.extra['unique_key'] ?? '';
    final Map<String, dynamic> filteredHeaders = Map.from(options.headers)
      ..remove('Authorization')
      ..remove('User-Agent')
      ..remove('content-length');

    String cacheKey =
        '${options.baseUrl}${options.path}?${jsonEncode(options.queryParameters)}';

    if (uniqueKey.isNotEmpty) {
      cacheKey += uniqueKey;
    }
    if (_uniqueWithHeader) {
      cacheKey += jsonEncode(filteredHeaders);
    }
    return cacheKey;
  }

  /// Intercepts outgoing requests and checks for cached responses.
  ///
  /// Caching is opted into per request through `options.extra['cache']`:
  /// - `true` — serve a valid cached response when available, otherwise continue
  ///   to the network.
  /// - `'only_cache'` — serve a valid cached response, otherwise reject the
  ///   request without hitting the network.
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final dynamic cacheMode = options.extra['cache'] ?? false;
    final bool isCache = cacheMode == true || cacheMode == 'only_cache';
    final bool isOnlyCache = cacheMode == 'only_cache';
    final bool isIgnoredHttpMethod =
        _defaultNoCacheHttpMethods.contains(options.method.toLowerCase());
    final int cacheValidity =
        options.extra['validate_time'] ?? _defaultCacheValidity;

    if (!isCache || isIgnoredHttpMethod) {
      handler.next(options);
      return;
    }

    try {
      final encryptedKey = _encryptCacheKey(_buildCacheKey(options));
      final cachedResponse = await _dbHelper.getResponse(encryptedKey);

      if (cachedResponse.isNotEmpty) {
        final responseString = cachedResponse['response'] as String? ?? '';
        final cachedData = _decryptData(responseString);

        final cachedTimestamp =
            DateTime.tryParse(cachedData['timestamp'] ?? '') ?? DateTime(1970);
        final specifiedCacheDate = options.extra['cache_updated_date'] != null
            ? DateTime.tryParse(options.extra['cache_updated_date'])
            : null;

        if ((specifiedCacheDate != null &&
                cachedTimestamp.isBefore(specifiedCacheDate)) ||
            DateTime.now().difference(cachedTimestamp).inMinutes <
                cacheValidity) {
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

      // only_cache mode: no valid cached data → reject without a network call.
      if (isOnlyCache) {
        handler.reject(_noCacheAvailable(options));
        return;
      }
    } catch (e, stackTrace) {
      log('Error fetching from cache: $e', stackTrace: stackTrace);

      // only_cache mode: lookup failed → reject without a network call.
      if (isOnlyCache) {
        handler.reject(_noCacheAvailable(options));
        return;
      }
    }

    handler.next(options);
  }

  /// Handles successful responses and caches them for future requests.
  ///
  /// A response is cached when it has data, a status code in the 200-300 range
  /// that is not in [noCacheStatusCodes], a method that is not in
  /// [noCacheHttpMethods], and — when provided — satisfies the [cacheWhen]
  /// predicate.
  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    final int? statusCode = response.statusCode;
    final bool isCacheableStatus = statusCode != null &&
        statusCode >= 200 &&
        statusCode <= 300 &&
        !_defaultNoCacheStatusCodes.contains(statusCode);
    final bool isCacheableMethod = !_defaultNoCacheHttpMethods
        .contains(response.requestOptions.method.toLowerCase());
    final bool passesCustomFilter = _cacheWhen?.call(response) ?? true;

    if (response.data != null &&
        isCacheableStatus &&
        isCacheableMethod &&
        passesCustomFilter) {
      final encryptedKey =
          _encryptCacheKey(_buildCacheKey(response.requestOptions));
      final encryptedData = _encryptData({
        'data': response.data,
        'timestamp': DateTime.now().toIso8601String(),
      });

      try {
        await _dbHelper.insertResponse(encryptedKey, encryptedData);
      } catch (e) {
        log('Error during cache insert: $e');
      }
    }

    handler.next(response);
  }

  /// Handles request errors and attempts to return cached data if enabled.
  ///
  /// When [getCachedDataWhenError] is `true` and the failure looks like a
  /// connectivity problem (timeouts, connection errors, socket exceptions),
  /// a cached response is served if one exists.
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
        (err.type == DioExceptionType.unknown &&
            err.error is SocketException)) {
      final encryptedKey = _encryptCacheKey(_buildCacheKey(err.requestOptions));

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

  DioException _noCacheAvailable(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'no_cache_available',
      );
}
