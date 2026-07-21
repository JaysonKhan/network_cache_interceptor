import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';
import 'package:network_cache_interceptor/src/aes_helper/aes_helper.dart';
import 'package:network_cache_interceptor/src/database_helper/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fake [HttpClientAdapter] that returns canned responses or throws, so the
/// full interceptor chain can be exercised without real network access.
class _FakeAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? _onFetch;
  Object? _error;
  int callCount = 0;

  void returnJson(
    Object? data, {
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    _error = null;
    _onFetch = (_) => ResponseBody.fromString(
          jsonEncode(data),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            ...headers,
          },
        );
  }

  void throwOffline() => _error = const SocketException('offline');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    if (_error != null) throw _error!;
    return _onFetch!(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _FakeAdapter adapter;

  Dio buildDio(NetworkCacheInterceptor interceptor) {
    return Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..interceptors.add(interceptor)
      ..httpClientAdapter = adapter;
  }

  setUp(() async {
    adapter = _FakeAdapter();
    NetworkCacheInterceptor.debugResetConfig();
    await NetworkCacheSQLHelper().clearDatabase();
  });

  group('Generic caching', () {
    test('caches a Map response and serves it from cache while valid',
        () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'message': 'v1'});
      final first = await dio.get('/posts', options: _cache());
      expect(first.data['message'], 'v1');
      expect(first.extra['from_cache'], isNull);

      adapter.returnJson({'message': 'v2'});
      final second = await dio.get('/posts', options: _cache());
      expect(second.data['message'], 'v1');
      expect(second.extra['from_cache'], true);
      expect(second.extra['cached_at'], isNotNull);
    });

    test('caches List responses and serves them when offline', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson([1, 2, 3]);
      final first = await dio.get('/list', options: _cache());
      expect(first.data, [1, 2, 3]);

      adapter.throwOffline();
      final offline = await dio.get('/list', options: _cache());
      expect(offline.data, [1, 2, 3]);
      expect(offline.extra['from_cache'], true);
    });

    test('does not serve expired cache', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'message': 'old'});
      await dio.get('/expiring', options: _cache());

      adapter.returnJson({'message': 'fresh'});
      final result = await dio.get(
        '/expiring',
        options: Options(extra: {'cache': true, 'validate_time': 0}),
      );
      expect(result.data['message'], 'fresh');
    });

    test('preserves original status code and headers on cache hit', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson(
        {'ok': true},
        status: 201,
        headers: {
          'x-custom': ['header-value'],
        },
      );
      await dio.get('/headers', options: _cache());

      adapter.throwOffline();
      final offline = await dio.get('/headers', options: _cache());
      expect(offline.statusCode, 201);
      expect(offline.headers.value('x-custom'), 'header-value');
    });
  });

  group('storeOnlyOptIn (NCI-1)', () {
    test('does not store responses that did not opt in (default)', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'message': 'private'});
      await dio.get('/private'); // no cache flag

      expect(await NetworkCacheSQLHelper().count(), 0);
    });

    test('stores all responses when storeOnlyOptIn is false', () async {
      final dio = buildDio(NetworkCacheInterceptor(storeOnlyOptIn: false));

      adapter.returnJson({'message': 'anything'});
      await dio.get('/anything'); // no cache flag

      expect(await NetworkCacheSQLHelper().count(), 1);
    });
  });

  group('refresh mode (NCI-2)', () {
    test('always hits the network, stores, and never serves from cache',
        () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'v': 1});
      await dio.get('/swr', options: _cache());

      adapter.returnJson({'v': 2});
      final refreshed = await dio.get('/swr', options: _refresh());
      expect(refreshed.data['v'], 2);
      expect(refreshed.extra['from_cache'], isNull);

      // The refreshed value must have replaced the cache.
      final cached = await dio.get('/swr', options: _onlyCache());
      expect(cached.data['v'], 2);
    });
  });

  group('config is applied once (NCI-3)', () {
    test('a later bare constructor does not wipe the configuration', () async {
      final dio = buildDio(NetworkCacheInterceptor(encryptionKey: 'my_key'));

      // A bare call must return the same, still-encrypted instance.
      final bare = NetworkCacheInterceptor();
      expect(identical(bare, NetworkCacheInterceptor.instance), isTrue);

      adapter.returnJson({'secret': 'ENC_MARKER'});
      await dio.get('/enc', options: _cache());

      final rows =
          await (await NetworkCacheSQLHelper().database).query('responses');
      for (final row in rows) {
        expect(row['response'].toString().contains('ENC_MARKER'), isFalse);
      }
    });
  });

  group('cacheWhen predicate', () {
    test('skips responses that do not satisfy the predicate', () async {
      final dio = buildDio(
        NetworkCacheInterceptor(
          cacheWhen: (r) => r.data is Map && r.data['success'] == true,
        ),
      );

      adapter.returnJson({'success': false});
      await dio.get('/guarded', options: _cache());

      adapter.throwOffline();
      await expectLater(
        dio.get('/guarded', options: _cache()),
        throwsA(isA<DioException>()),
      );
    });

    test('caches responses that satisfy the predicate', () async {
      final dio = buildDio(
        NetworkCacheInterceptor(
          cacheWhen: (r) => r.data is Map && r.data['success'] == true,
        ),
      );

      adapter.returnJson({'success': true});
      await dio.get('/guarded', options: _cache());

      adapter.throwOffline();
      final offline = await dio.get('/guarded', options: _cache());
      expect(offline.data['success'], true);
    });
  });

  group('only_cache mode', () {
    test('rejects with a CacheMissException when cache is empty', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      await expectLater(
        dio.get('/only', options: _onlyCache()),
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having((e) => e.error, 'error', isA<CacheMissException>()),
        ),
      );
      expect(adapter.callCount, 0, reason: 'network must not be called');
    });

    test('serves cached data without hitting the network', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'message': 'stored'});
      await dio.get('/only', options: _cache());

      final callsBefore = adapter.callCount;
      final result = await dio.get('/only', options: _onlyCache());
      expect(result.data['message'], 'stored');
      expect(result.extra['from_cache'], true);
      expect(adapter.callCount, callsBefore);
    });
  });

  group('offlineFallbackOnlyOptIn (NCI-7)', () {
    test('does not serve cache offline for non-opt-in requests (default)',
        () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'message': 'cached'});
      await dio.get('/fb', options: _cache()); // populate cache

      adapter.throwOffline();
      await expectLater(
        dio.get('/fb'), // no opt-in
        throwsA(isA<DioException>()),
      );
    });

    test('serves cache offline for any request when flag is false', () async {
      final dio =
          buildDio(NetworkCacheInterceptor(offlineFallbackOnlyOptIn: false));

      adapter.returnJson({'message': 'cached'});
      await dio.get('/fb', options: _cache());

      adapter.throwOffline();
      final offline = await dio.get('/fb'); // no opt-in, still served
      expect(offline.data['message'], 'cached');
    });
  });

  group('Exclusions', () {
    test('does not cache excluded status codes', () async {
      final dio = buildDio(NetworkCacheInterceptor());
      dio.options.validateStatus = (_) => true;

      adapter.returnJson({'message': 'unauthorized'}, status: 401);
      await dio.get('/secure', options: _cache());

      expect(await NetworkCacheSQLHelper().count(), 0);
    });
  });

  group('Eviction & expiry (NCI-8)', () {
    test('maxEntries evicts the oldest entries', () async {
      final dio = buildDio(NetworkCacheInterceptor(maxEntries: 2));

      for (final path in ['/a', '/b', '/c']) {
        adapter.returnJson({'p': path});
        await dio.get(path, options: _cache());
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(await NetworkCacheSQLHelper().count(), 2);
      await expectLater(
        dio.get('/a', options: _onlyCache()),
        throwsA(isA<DioException>()),
      );
    });

    test('deleteExpired removes entries older than maxAge', () async {
      final interceptor = NetworkCacheInterceptor();
      final dio = buildDio(interceptor);

      adapter.returnJson({'x': 1});
      await dio.get('/exp', options: _cache());

      expect(await interceptor.deleteExpired(const Duration(minutes: 1)), 0);
      expect(await interceptor.deleteExpired(Duration.zero), 1);
      expect(await NetworkCacheSQLHelper().count(), 0);
    });
  });

  group('invalidate (NCI-9)', () {
    test('removes all query variants of an endpoint', () async {
      final interceptor = NetworkCacheInterceptor();
      final dio = buildDio(interceptor);

      adapter.returnJson({'page': 1});
      await dio.get('/orders', queryParameters: {'page': 1}, options: _cache());
      adapter.returnJson({'page': 2});
      await dio.get('/orders', queryParameters: {'page': 2}, options: _cache());

      final removed =
          await interceptor.invalidate('https://example.com/orders');
      expect(removed, 2);
      expect(await NetworkCacheSQLHelper().count(), 0);
    });

    test('works with encryption enabled', () async {
      final interceptor = NetworkCacheInterceptor(encryptionKey: 'k');
      final dio = buildDio(interceptor);

      adapter.returnJson({'ok': true});
      await dio.get('/orders', options: _cache());

      final removed =
          await interceptor.invalidate('https://example.com/orders');
      expect(removed, 1);
    });
  });

  group('key rotation (NCI-12)', () {
    test('entries written with an old key are dropped after rotation',
        () async {
      var dio = buildDio(NetworkCacheInterceptor(encryptionKey: 'key_aaa'));
      adapter.returnJson({'v': 'secret'});
      await dio.get('/rot', options: _cache());
      expect(await NetworkCacheSQLHelper().count(), 1);

      // Rotate the key.
      NetworkCacheInterceptor.debugResetConfig();
      dio = buildDio(NetworkCacheInterceptor(encryptionKey: 'key_bbb'));

      await expectLater(
        dio.get('/rot', options: _onlyCache()),
        throwsA(isA<DioException>()),
      );
      // The unreadable entry was pruned.
      expect(await NetworkCacheSQLHelper().count(), 0);
    });
  });

  group('Duration validity (NCI-11)', () {
    test('cacheValidity as Duration keeps entries fresh', () async {
      final dio = buildDio(
          NetworkCacheInterceptor(cacheValidity: const Duration(hours: 1)));

      adapter.returnJson({'v': 1});
      await dio.get('/dur', options: _cache());

      adapter.returnJson({'v': 2});
      final served = await dio.get('/dur', options: _cache());
      expect(served.data['v'], 1);
    });

    test('per-request validate_time accepts a Duration', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson({'v': 1});
      await dio.get('/dur', options: _cache());

      adapter.returnJson({'v': 2});
      final refetched = await dio.get(
        '/dur',
        options:
            Options(extra: {'cache': true, 'validate_time': Duration.zero}),
      );
      expect(refetched.data['v'], 2);
    });
  });

  group('cachedThenFresh (NCI-10)', () {
    test('emits cached then fresh', () async {
      final interceptor = NetworkCacheInterceptor();
      final dio = buildDio(interceptor);

      adapter.returnJson({'v': 1});
      await dio.get('/swr', options: _cache());

      adapter.returnJson({'v': 2});
      final emitted = await interceptor.cachedThenFresh(dio, '/swr').toList();

      expect(emitted.length, 2);
      expect(emitted[0].data['v'], 1);
      expect(emitted[0].extra['from_cache'], true);
      expect(emitted[1].data['v'], 2);
      expect(emitted[1].extra['from_cache'], isNull);
    });

    test('emits only fresh when nothing is cached', () async {
      final interceptor = NetworkCacheInterceptor();
      final dio = buildDio(interceptor);

      adapter.returnJson({'v': 3});
      final emitted = await interceptor.cachedThenFresh(dio, '/swr').toList();

      expect(emitted.length, 1);
      expect(emitted[0].data['v'], 3);
    });
  });

  group('Encryption', () {
    test('round-trips encrypted data and stores ciphertext only', () async {
      const marker = 'TOP_SECRET_MARKER';
      final dio = buildDio(NetworkCacheInterceptor(encryptionKey: 'my_key'));

      adapter.returnJson({'secret': marker});
      await dio.get('/enc', options: _cache());

      final rows =
          await (await NetworkCacheSQLHelper().database).query('responses');
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row['request'].toString().contains('/enc'), isFalse);
        expect(row['response'].toString().contains(marker), isFalse);
      }

      adapter.throwOffline();
      final offline = await dio.get('/enc', options: _cache());
      expect(offline.data['secret'], marker);
    });

    test('assert fails for an empty encryption key', () {
      expect(
        () => NetworkCacheInterceptor(encryptionKey: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert fails for a key longer than 32 characters', () {
      expect(
        () => NetworkCacheInterceptor(encryptionKey: 'a' * 33),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AESHelper', () {
    test('deterministic encryption is stable for equal inputs', () {
      final helper = AESHelper('key123');
      expect(
        helper.encryptDeterministic('cache-key'),
        helper.encryptDeterministic('cache-key'),
      );
    });

    test('gcm encryption round-trips and randomizes ciphertext', () {
      final helper = AESHelper('key123');
      const text = 'hello world';
      final a = helper.encrypt(text);
      final b = helper.encrypt(text);
      expect(a, isNot(b));
      expect(helper.decrypt(a), text);
      expect(helper.decrypt(b), text);
    });
  });
}

Options _cache() => Options(extra: {'cache': true});

Options _onlyCache() => Options(extra: {'cache': 'only_cache'});

Options _refresh() => Options(extra: {'cache': 'refresh'});
