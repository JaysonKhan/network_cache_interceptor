
# Network Cache Interceptor

`Network Cache Interceptor` is a custom Dio interceptor for caching network requests. It delivers cached data when offline, supports stale-while-revalidate, optional at-rest encryption, and fine-grained cache lifecycle control.

---

## 📦 Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  network_cache_interceptor: ^3.0.0
```

Or install it via `flutter pub add`:

```bash
flutter pub add network_cache_interceptor
```

---

## 🚀 What’s New in Version 3.0.0

Version **3.0.0** is a major release focused on privacy-by-default, cache lifecycle control, and observability.

⚠️ **Breaking changes:**
- **Opt-in storage by default** (`storeOnlyOptIn: true`) — only requests that opt into caching (`extra['cache']` set) are written to disk. Set `storeOnlyOptIn: false` for the old “cache every GET” behavior.
- **Opt-in offline fallback by default** (`offlineFallbackOnlyOptIn: true`).
- **Configuration is applied once** — the first `NetworkCacheInterceptor(...)` configures the singleton; later calls return it unchanged. Use `NetworkCacheInterceptor.instance` to access it.

✅ **New features:**
- **`'refresh'` mode** + **`cachedThenFresh()`** stream for stale-while-revalidate.
- **Cache-hit markers** (`response.extra['from_cache']`, `['cached_at']`).
- **Original status code & headers** are preserved on cache hits.
- **`CacheMissException`** for `only_cache` misses.
- **Lifecycle API**: `invalidate()`, `deleteExpired()`, `maxEntries` eviction.
- **Automatic encryption key rotation** and **`Duration`** validity support.

---

## 🚀 Usage

### 1. Configure `Dio`

```dart
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';

void main() {
  final dio = Dio();

  dio.interceptors.add(
    NetworkCacheInterceptor(
      noCacheStatusCodes: [401, 403, 304],
      noCacheHttpMethods: ['POST', 'PUT'], // Methods that are never cached
      cacheValidity: const Duration(minutes: 30),
      getCachedDataWhenError: true,
      maxEntries: 200,                 // Optional: cap stored entries (LRU-ish)
      // storeOnlyOptIn defaults to true — only opt-in requests are stored.
      encryptionKey: 'my_secret_key',  // Optional: encrypt cache at rest
      cacheWhen: (response) =>         // Optional: only cache when this is true
          response.data is Map && response.data['success'] == true,
    ),
  );
}
```

> Configure the interceptor **once** at startup. Later `NetworkCacheInterceptor()` calls return the same instance and ignore their arguments. Reach it anywhere with `NetworkCacheInterceptor.instance`.

---

### 2. Cache Modes

Caching is opted into per request via `options.extra['cache']`:

| Value          | Behavior                                                                 |
|----------------|--------------------------------------------------------------------------|
| `true`         | Serve a valid cached response if present, else hit the network and store |
| `'only_cache'` | Serve a valid cached response, else fail fast (no network call)          |
| `'refresh'`    | Always hit the network and store, but never serve from cache             |
| absent/`false` | No caching for this request                                              |

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {
      'cache': true,
      'validate_time': const Duration(minutes: 60), // int minutes also accepted
    },
  ),
);
```

---

### 3. Use `unique_key` for More Precise Caching

`unique_key` ensures different cache entries for similar requests:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {'cache': true, 'unique_key': 'user_123'},
  ),
);
```

---

### 4. Offline-Only Reads with `only_cache`

Return cached data instantly and **skip the network entirely**. If no valid cache exists, the request fails fast with a `DioException` carrying a `CacheMissException`:

```dart
try {
  final response = await dio.get(
    '/posts',
    options: Options(extra: {'cache': 'only_cache'}),
  );
  print(response.data); // Served from cache, no network call
} on DioException catch (e) {
  if (e.error is CacheMissException) {
    print('No cached data available');
  }
}
```

---

### 5. Stale-While-Revalidate with `cachedThenFresh`

Render cached data instantly, then update when the network responds:

```dart
NetworkCacheInterceptor.instance
    .cachedThenFresh(dio, '/orders')
    .listen((response) {
  final fromCache = response.extra['from_cache'] == true;
  render(response.data, stale: fromCache);
});
```

The stream emits the cached response first (if any), then the fresh network response. Prefer this over hand-rolling the two-legged pattern in every bloc/provider.

---

### 6. Detect Cache Hits

Served-from-cache responses are tagged, so the UI can show an “offline data” banner:

```dart
if (response.extra['from_cache'] == true) {
  final cachedAt = DateTime.parse(response.extra['cached_at']);
  showBanner('Showing data from ${cachedAt.toLocal()}');
}
```

Cache hits also restore the original `statusCode` and response headers.

---

### 7. Encrypt the Cache at Rest

Pass an `encryptionKey` (1-32 characters) to encrypt cached data and cache keys:

```dart
dio.interceptors.add(
  NetworkCacheInterceptor(encryptionKey: 'my_secret_key'),
);
```

Response bodies use AES-GCM (random IV per entry); cache keys use deterministic AES-CBC so lookups stay consistent. If the key changes, entries written with the old key are detected and purged automatically.

---

### 8. Invalidate, Expire, and Clear

```dart
final cache = NetworkCacheInterceptor.instance;

// Remove every cached variant of one endpoint (e.g. after a POST /orders).
await cache.invalidate('https://api.example.com/orders');

// Prune entries older than a duration.
await cache.deleteExpired(const Duration(days: 7));

// Remove everything.
await cache.clearDatabase();
```

The `maxEntries` constructor option caps the store and evicts the oldest entries automatically.

---

## ⚙️ Configuration

| Parameter                  | Description                                                    | Default                |
|----------------------------|---------------------------------------------------------------|------------------------|
| `noCacheStatusCodes`       | HTTP status codes that should not be cached                   | `[401, 403, 304]`      |
| `noCacheHttpMethods`       | HTTP methods that should not be cached                        | `['POST']`             |
| `cacheValidityMinutes`     | Cache validity in minutes (ignored if `cacheValidity` is set) | `30`                   |
| `cacheValidity`            | Cache validity as a `Duration`                                | `null`                 |
| `getCachedDataWhenError`   | Return cached data on connectivity errors                     | `true`                 |
| `uniqueWithHeader`         | Use request headers for unique cache keys                     | `false`                |
| `storeOnlyOptIn`           | Only store responses whose request opted in                   | `true`                 |
| `offlineFallbackOnlyOptIn` | Only use the offline fallback for opt-in requests             | `true`                 |
| `maxEntries`               | Cap on stored entries (oldest evicted)                        | `null` (unlimited)     |
| `cacheWhen`                | Predicate to restrict which responses get cached              | `null` (cache all)     |
| `encryptionKey`            | AES key (1-32 chars) to encrypt the cache at rest             | `null` (no encryption) |

Per-request `extra` keys: `cache`, `validate_time` (int minutes or `Duration`), `unique_key`, `cache_updated_date`.

---

## 🍳 Recipes

**Cache-then-network (stale-while-revalidate):**

```dart
NetworkCacheInterceptor.instance
    .cachedThenFresh(dio, '/dashboard')
    .listen((res) => emit(DashboardState(res.data, stale: res.extra['from_cache'] == true)));
```

**Privacy gating — cache only non-sensitive, successful bodies:**

```dart
NetworkCacheInterceptor(
  storeOnlyOptIn: true, // never store anything not explicitly opted in
  cacheWhen: (r) => r.data is Map && r.data['success'] == true,
);
```

---

## 🔧 Technical Details

- **Offline Mode:** Cached responses are returned on timeouts, no connection, or socket errors.
- **Opt-in by Default:** Only requests that set `extra['cache']` are stored (configurable).
- **Encryption at Rest:** Optional AES for data (AES-GCM) and keys (AES-CBC), with automatic key-rotation cleanup.
- **Observability:** `from_cache` / `cached_at` markers and preserved status codes & headers.
- **Header Filtering:** Ignores `Authorization`, `User-Agent`, and `content-length` in cache keys.
- **Robust Storage:** Local SQLite with size (`maxEntries`) and age (`deleteExpired`) controls.

---

## 🛡️ License

This project is licensed under the [MIT](./LICENSE) License.

---

## 💬 Additional Information

For more information or to contribute, visit our GitHub page.

---

## 📦 Explore More

If you enjoy using this package, check out:

- **[Telegram Bot Crashlytics](https://pub.dev/packages/telegram_bot_crashlytics)** – Send app crashes and errors to a Telegram chat for easier monitoring.

---

Thanks for using **Network Cache Interceptor**! 🚀
