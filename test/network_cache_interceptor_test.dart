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
  ResponseBody Function(RequestOptions options)? onFetch;
  Object? error;
  int callCount = 0;

  void returnJson(Object? data, {int status = 200}) {
    error = null;
    onFetch = (_) => ResponseBody.fromString(
          jsonEncode(data),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
  }

  void throwOffline() => error = const SocketException('offline');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    if (error != null) throw error!;
    return onFetch!(options);
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
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..interceptors.add(interceptor)
      ..httpClientAdapter = adapter;
    return dio;
  }

  setUp(() async {
    adapter = _FakeAdapter();
    // Reset shared cache state before each test.
    await NetworkCacheInterceptor().clearDatabase();
  });

  group('Generic caching', () {
    test('caches a Map response and serves it from cache while valid',
        () async {
      final dio = buildDio(NetworkCacheInterceptor(cacheValidityMinutes: 30));

      adapter.returnJson({'message': 'v1'});
      final first = await dio.get('/posts', options: _cache());
      expect(first.data['message'], 'v1');

      // The network now returns something different; a cached hit must win.
      adapter.returnJson({'message': 'v2'});
      final second = await dio.get('/posts', options: _cache());
      expect(second.data['message'], 'v1');
    });

    test('caches List responses and serves them when offline', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      adapter.returnJson([1, 2, 3]);
      final first = await dio.get('/list', options: _cache());
      expect(first.data, [1, 2, 3]);

      adapter.throwOffline();
      final offline = await dio.get('/list', options: _cache());
      expect(offline.data, [1, 2, 3]);
    });

    test('does not serve expired cache', () async {
      final dio = buildDio(NetworkCacheInterceptor(cacheValidityMinutes: 30));

      adapter.returnJson({'message': 'old'});
      await dio.get('/expiring', options: _cache());

      // validate_time: 0 makes any existing entry immediately stale.
      adapter.returnJson({'message': 'fresh'});
      final result = await dio.get(
        '/expiring',
        options: Options(extra: {'cache': true, 'validate_time': 0}),
      );
      expect(result.data['message'], 'fresh');
    });
  });

  group('cacheWhen predicate', () {
    test('skips responses that do not satisfy the predicate', () async {
      final dio = buildDio(
        NetworkCacheInterceptor(
          cacheWhen: (r) => r.data is Map && r.data['success'] == true,
        ),
      );

      adapter.returnJson({'success': false, 'data': 'nope'});
      await dio.get('/guarded', options: _cache());

      // Nothing was cached, so an offline retry must fail.
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

      adapter.returnJson({'success': true, 'data': 'ok'});
      await dio.get('/guarded', options: _cache());

      adapter.throwOffline();
      final offline = await dio.get('/guarded', options: _cache());
      expect(offline.data['success'], true);
    });
  });

  group('only_cache mode', () {
    test('rejects without hitting the network when cache is empty', () async {
      final dio = buildDio(NetworkCacheInterceptor());

      await expectLater(
        dio.get('/only', options: _onlyCache()),
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having((e) => e.message, 'message', 'no_cache_available'),
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
      expect(adapter.callCount, callsBefore, reason: 'served from cache');
    });
  });

  group('Exclusions', () {
    test('does not cache excluded status codes', () async {
      final dio = buildDio(NetworkCacheInterceptor());
      dio.options.validateStatus = (_) => true;

      adapter.returnJson({'message': 'unauthorized'}, status: 401);
      await dio.get('/secure', options: _cache());

      adapter.throwOffline();
      await expectLater(
        dio.get('/secure', options: _cache()),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('Encryption', () {
    test('round-trips encrypted data and stores ciphertext only', () async {
      const marker = 'TOP_SECRET_MARKER';
      final dio = buildDio(NetworkCacheInterceptor(encryptionKey: 'my_key'));

      adapter.returnJson({'secret': marker});
      await dio.get('/enc', options: _cache());

      // Raw rows must not contain the plaintext marker.
      final db = await NetworkCacheSQLHelper().database;
      final rows = await db.query('responses');
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row['request'].toString().contains('/enc'), isFalse);
        expect(row['response'].toString().contains(marker), isFalse);
      }

      // Decryption on read still returns the original data.
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
