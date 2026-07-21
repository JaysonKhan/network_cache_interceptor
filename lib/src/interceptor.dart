import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:network_cache_interceptor/src/aes_helper/aes_helper.dart';
import 'package:network_cache_interceptor/src/database_helper/database_helper.dart';
import 'package:network_cache_interceptor/src/exceptions.dart';

/// Signature for a callback that decides whether a successful [Response]
/// should be cached. Return `true` to cache the response, `false` to skip it.
///
/// This runs in addition to the built-in checks (status code range and
/// no-cache HTTP methods), so it can only further restrict what gets cached.
typedef CacheWhenPredicate = bool Function(Response response);

/// Sentinel used to derive a stable fingerprint of the encryption key so key
/// rotation can be detected and stale entries dropped.
const String _keyCheckSentinel = '__nci_key_check__';

/// A Dio interceptor for caching network requests.
///
/// Stores successful responses in a local SQLite database and serves them back
/// when caching is requested or when the network is unavailable.
///
/// ## Per-request modes (`options.extra['cache']`)
/// * `true` — serve a valid cached response if present, otherwise hit the
///   network and store the result.
/// * `'only_cache'` — serve a valid cached response, otherwise fail fast with a
///   [DioException] carrying a [CacheMissException] (no network call).
/// * `'refresh'` — always hit the network and store the result, but never serve
///   from cache. Combine with `'only_cache'` for stale-while-revalidate, or use
///   [cachedThenFresh].
///
/// ## Configuration is applied once
/// The interceptor is a singleton. The first call to [NetworkCacheInterceptor.new]
/// applies the configuration; later calls return the same instance and ignore
/// their arguments, so `NetworkCacheInterceptor().clearDatabase()` never wipes
/// your options. Use [instance] to reach the configured interceptor.
class NetworkCacheInterceptor extends Interceptor {
  static final NetworkCacheInterceptor _instance =
      NetworkCacheInterceptor._internal();
  final NetworkCacheSQLHelper _dbHelper = NetworkCacheSQLHelper();

  /// Whether [NetworkCacheInterceptor.new] has already applied a configuration.
  static bool _configured = false;

  List<int> _defaultNoCacheStatusCodes;
  Set<String> _defaultNoCacheHttpMethods;
  Duration _defaultCacheValidity;
  bool _getCachedDataWhenError;
  bool _uniqueWithHeader;
  bool _storeOnlyOptIn;
  bool _offlineFallbackOnlyOptIn;
  int? _maxEntries;
  AESHelper? _aesHelper;
  CacheWhenPredicate? _cacheWhen;
  bool _keyConsistencyEnsured = false;

  /// The configured singleton instance.
  static NetworkCacheInterceptor get instance => _instance;

  /// Creates (and, on the first call, configures) the interceptor.
  ///
  /// - [noCacheStatusCodes]: Status codes that should not be cached.
  /// - [cacheValidityMinutes]: Cache lifetime in minutes (ignored if
  ///   [cacheValidity] is provided).
  /// - [cacheValidity]: Cache lifetime as a [Duration]; takes precedence over
  ///   [cacheValidityMinutes].
  /// - [getCachedDataWhenError]: Serve cached data on connectivity failures.
  /// - [uniqueWithHeader]: Include request headers in the cache key.
  /// - [noCacheHttpMethods]: HTTP methods that should never be cached
  ///   (case-insensitive).
  /// - [storeOnlyOptIn]: When `true` (the default), only responses whose request
  ///   opted into caching (`extra['cache']` set) are written to disk. Set to
  ///   `false` to cache every eligible response.
  /// - [offlineFallbackOnlyOptIn]: When `true` (the default), the offline
  ///   fallback in [onError] only looks up the cache for opt-in requests.
  /// - [maxEntries]: Optional cap on the number of stored entries; the oldest
  ///   entries are evicted once the cap is exceeded.
  /// - [cacheWhen]: Optional predicate to further restrict which responses are
  ///   cached, e.g. `(r) => r.data is Map && r.data['success'] == true`.
  /// - [encryptionKey]: Optional AES key (1-32 characters). When provided, cache
  ///   keys and response data are encrypted before being stored.
  factory NetworkCacheInterceptor({
    List<int> noCacheStatusCodes = const [401, 403, 304],
    List<String> noCacheHttpMethods = const ['POST'],
    int cacheValidityMinutes = 30,
    Duration? cacheValidity,
    bool getCachedDataWhenError = true,
    bool uniqueWithHeader = false,
    bool storeOnlyOptIn = true,
    bool offlineFallbackOnlyOptIn = true,
    int? maxEntries,
    CacheWhenPredicate? cacheWhen,
    String? encryptionKey,
  }) {
    // Configuration is applied only once (see class docs).
    if (_configured) return _instance;

    assert(
      encryptionKey == null ||
          (encryptionKey.isNotEmpty && encryptionKey.length <= 32),
      'Encryption key must be between 1 and 32 characters',
    );
    assert(
      maxEntries == null || maxEntries > 0,
      'maxEntries must be greater than 0',
    );

    _instance._defaultNoCacheStatusCodes = noCacheStatusCodes;
    _instance._defaultCacheValidity =
        cacheValidity ?? Duration(minutes: cacheValidityMinutes);
    _instance._getCachedDataWhenError = getCachedDataWhenError;
    _instance._uniqueWithHeader = uniqueWithHeader;
    _instance._storeOnlyOptIn = storeOnlyOptIn;
    _instance._offlineFallbackOnlyOptIn = offlineFallbackOnlyOptIn;
    _instance._maxEntries = maxEntries;
    _instance._defaultNoCacheHttpMethods =
        noCacheHttpMethods.map((e) => e.toLowerCase()).toSet();
    _instance._cacheWhen = cacheWhen;
    _instance._aesHelper =
        encryptionKey != null ? AESHelper(encryptionKey) : null;
    _instance._keyConsistencyEnsured = false;
    _configured = true;
    return _instance;
  }

  NetworkCacheInterceptor._internal()
      : _defaultNoCacheStatusCodes = const [401, 403, 304],
        _defaultNoCacheHttpMethods = const {'post'},
        _defaultCacheValidity = const Duration(minutes: 30),
        _getCachedDataWhenError = true,
        _uniqueWithHeader = false,
        _storeOnlyOptIn = true,
        _offlineFallbackOnlyOptIn = true,
        _maxEntries = null,
        _cacheWhen = null,
        _aesHelper = null;

  /// Resets the singleton configuration. For tests only.
  @visibleForTesting
  static void debugResetConfig() => _configured = false;

  // ---------------------------------------------------------------------------
  // Encryption helpers
  // ---------------------------------------------------------------------------

  /// Encrypts the cache key deterministically (fixed IV) so the same key always
  /// maps to the same stored value — required for consistent lookups.
  String _encryptCacheKey(String cacheKey) {
    if (_aesHelper == null) return cacheKey;
    return _aesHelper!.encryptDeterministic(cacheKey);
  }

  /// A stable fingerprint of the current encryption key (empty when disabled).
  String get _keyFingerprint => _aesHelper == null
      ? ''
      : _aesHelper!.encryptDeterministic(_keyCheckSentinel);

  /// Serializes [data] to JSON, encrypting it with AES-GCM when enabled.
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

  /// Purges entries written under a different encryption key once per
  /// configuration, so a rotated key does not leave unreadable rows behind.
  Future<void> _ensureKeyConsistency() async {
    if (_keyConsistencyEnsured) return;
    _keyConsistencyEnsured = true;
    try {
      await _dbHelper.deleteByKeyHashNot(_keyFingerprint);
    } catch (e) {
      log('Error pruning stale-key entries: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Key building
  // ---------------------------------------------------------------------------

  /// The endpoint tag (base URL + path) used for targeted invalidation.
  String _urlTag(RequestOptions options) =>
      _encryptCacheKey('${options.baseUrl}${options.path}');

  /// Builds the full cache key for a request.
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

  /// Whether a request opted into caching via `extra['cache']`.
  bool _optedIn(RequestOptions options) {
    final mode = options.extra['cache'];
    return mode == true || mode == 'only_cache' || mode == 'refresh';
  }

  /// Resolves the effective cache validity for a request.
  Duration _validityFor(RequestOptions options) {
    final v = options.extra['validate_time'];
    if (v is Duration) return v;
    if (v is int) return Duration(minutes: v);
    return _defaultCacheValidity;
  }

  // ---------------------------------------------------------------------------
  // Cache read/serve
  // ---------------------------------------------------------------------------

  /// Reads a cached payload for [key], honouring key rotation. Returns `null`
  /// when there is no usable entry (missing or encrypted with an old key).
  Future<Map<String, dynamic>?> _readCache(String key) async {
    final row = await _dbHelper.getResponse(key);
    if (row.isEmpty) return null;

    if ((row['key_hash'] as String? ?? '') != _keyFingerprint) {
      // Key changed since this entry was written — it can no longer be read.
      await _dbHelper.deleteResponse(key);
      return null;
    }

    try {
      return _decryptData(row['response'] as String? ?? '');
    } catch (e) {
      log('Error decrypting cache entry: $e');
      await _dbHelper.deleteResponse(key);
      return null;
    }
  }

  /// Builds a [Response] from a decrypted cache [payload], restoring the
  /// original status code and headers and tagging it as a cache hit.
  Response _responseFromCache(
      RequestOptions options, Map<String, dynamic> payload) {
    return Response(
      requestOptions: options,
      data: payload['data'],
      statusCode: payload['statusCode'] as int? ?? 200,
      headers: _headersFrom(payload['headers']),
      extra: {
        'from_cache': true,
        'cached_at': payload['timestamp'],
      },
    );
  }

  Headers _headersFrom(dynamic stored) {
    final headers = Headers();
    if (stored is Map) {
      stored.forEach((key, value) {
        if (value is List) {
          headers.set(key.toString(), value.map((e) => e.toString()).toList());
        } else if (value != null) {
          headers.set(key.toString(), value.toString());
        }
      });
    }
    return headers;
  }

  // ---------------------------------------------------------------------------
  // Interceptor overrides
  // ---------------------------------------------------------------------------

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    await _ensureKeyConsistency();
    final dynamic cacheMode = options.extra['cache'] ?? false;
    final bool isOnlyCache = cacheMode == 'only_cache';
    final bool readsCache = cacheMode == true || isOnlyCache;
    final bool isIgnoredHttpMethod =
        _defaultNoCacheHttpMethods.contains(options.method.toLowerCase());

    // 'refresh' and non-cached requests go straight to the network (they are
    // stored, if eligible, in onResponse).
    if (!readsCache || isIgnoredHttpMethod) {
      handler.next(options);
      return;
    }

    try {
      final key = _encryptCacheKey(_buildCacheKey(options));
      final payload = await _readCache(key);

      if (payload != null && _isFresh(payload, options)) {
        handler.resolve(_responseFromCache(options, payload));
        return;
      }

      if (isOnlyCache) {
        handler.reject(_cacheMiss(options));
        return;
      }
    } catch (e, stackTrace) {
      log('Error fetching from cache: $e', stackTrace: stackTrace);
      if (isOnlyCache) {
        handler.reject(_cacheMiss(options));
        return;
      }
    }

    handler.next(options);
  }

  /// Whether a cached [payload] is still valid for [options].
  bool _isFresh(Map<String, dynamic> payload, RequestOptions options) {
    final cachedTimestamp =
        DateTime.tryParse(payload['timestamp'] ?? '') ?? DateTime(1970);
    final specifiedCacheDate = options.extra['cache_updated_date'] != null
        ? DateTime.tryParse(options.extra['cache_updated_date'])
        : null;

    if (specifiedCacheDate != null &&
        cachedTimestamp.isBefore(specifiedCacheDate)) {
      return true;
    }
    return DateTime.now().difference(cachedTimestamp) < _validityFor(options);
  }

  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    await _ensureKeyConsistency();
    if (_shouldStore(response)) {
      final options = response.requestOptions;
      final key = _encryptCacheKey(_buildCacheKey(options));
      final payload = _encryptData({
        'data': response.data,
        'statusCode': response.statusCode,
        'headers': response.headers.map,
        'timestamp': DateTime.now().toIso8601String(),
      });

      try {
        await _dbHelper.insertResponse(
          request: key,
          url: _urlTag(options),
          keyHash: _keyFingerprint,
          response: payload,
        );
        if (_maxEntries != null) {
          await _dbHelper.enforceMaxEntries(_maxEntries!);
        }
      } catch (e) {
        log('Error during cache insert: $e');
      }
    }

    handler.next(response);
  }

  /// Whether [response] passes every gate required to be cached.
  bool _shouldStore(Response response) {
    final int? statusCode = response.statusCode;
    final bool cacheableStatus = statusCode != null &&
        statusCode >= 200 &&
        statusCode <= 300 &&
        !_defaultNoCacheStatusCodes.contains(statusCode);
    final bool cacheableMethod = !_defaultNoCacheHttpMethods
        .contains(response.requestOptions.method.toLowerCase());
    final bool optInOk = !_storeOnlyOptIn || _optedIn(response.requestOptions);
    final bool customOk = _cacheWhen?.call(response) ?? true;

    return response.data != null &&
        cacheableStatus &&
        cacheableMethod &&
        optInOk &&
        customOk;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    await _ensureKeyConsistency();
    final bool fallbackAllowed = _getCachedDataWhenError &&
        (!_offlineFallbackOnlyOptIn || _optedIn(err.requestOptions));

    if (fallbackAllowed && _isConnectivityError(err)) {
      final key = _encryptCacheKey(_buildCacheKey(err.requestOptions));
      try {
        final payload = await _readCache(key);
        if (payload != null) {
          handler.resolve(_responseFromCache(err.requestOptions, payload));
          return;
        }
      } catch (e, stackTrace) {
        log('Error fetching from cache: $e', stackTrace: stackTrace);
      }
    }

    handler.next(err);
  }

  bool _isConnectivityError(DioException err) =>
      err.type == DioExceptionType.connectionTimeout ||
      err.type == DioExceptionType.receiveTimeout ||
      err.type == DioExceptionType.sendTimeout ||
      err.type == DioExceptionType.connectionError ||
      (err.type == DioExceptionType.unknown && err.error is SocketException);

  // ---------------------------------------------------------------------------
  // Public cache-management API
  // ---------------------------------------------------------------------------

  /// Clears all cached responses.
  Future<void> clearDatabase() async {
    try {
      await _dbHelper.clearDatabase();
      log('Database cleared successfully');
    } catch (e) {
      log('Error clearing database: $e');
    }
  }

  /// Invalidates every cached entry for a given endpoint.
  ///
  /// [baseUrlWithPath] must match `RequestOptions.baseUrl + RequestOptions.path`
  /// (e.g. `'https://api.example.com/orders'`). All query and `unique_key`
  /// variants of that endpoint are removed. Works with encryption enabled.
  Future<int> invalidate(String baseUrlWithPath) async {
    try {
      return await _dbHelper.deleteByUrl(_encryptCacheKey(baseUrlWithPath));
    } catch (e) {
      log('Error invalidating cache: $e');
      return 0;
    }
  }

  /// Deletes cached entries older than [maxAge].
  Future<int> deleteExpired(Duration maxAge) async {
    try {
      return await _dbHelper.deleteExpired(DateTime.now().subtract(maxAge));
    } catch (e) {
      log('Error deleting expired entries: $e');
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Stale-while-revalidate helper
  // ---------------------------------------------------------------------------

  /// Emits the cached response first (if any), then the fresh network response.
  ///
  /// This is the two-legged stale-while-revalidate pattern: the UI can render
  /// cached data instantly, then update when the network responds. The cached
  /// leg is skipped silently when nothing is cached.
  ///
  /// ```dart
  /// NetworkCacheInterceptor.instance
  ///     .cachedThenFresh(dio, '/orders')
  ///     .listen((response) => render(response.data));
  /// ```
  Stream<Response> cachedThenFresh(
    Dio dio,
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async* {
    try {
      yield await dio.get(
        path,
        queryParameters: queryParameters,
        options: _withCacheMode(options, 'only_cache'),
      );
    } on DioException catch (e) {
      if (e.error is! CacheMissException) rethrow;
    }

    yield await dio.get(
      path,
      queryParameters: queryParameters,
      options: _withCacheMode(options, 'refresh'),
    );
  }

  Options _withCacheMode(Options? base, String mode) {
    final options = base ?? Options();
    final extra = Map<String, dynamic>.from(options.extra ?? {});
    extra['cache'] = mode;
    return options.copyWith(extra: extra);
  }

  DioException _cacheMiss(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: CacheMissException(options.path),
        message: 'no_cache_available',
      );
}
