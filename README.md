
# Network Cache Interceptor

`Network Cache Interceptor` is a custom Dio interceptor for caching network requests. It delivers cached data when offline and improves network request handling.

---

## 📦 Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  network_cache_interceptor: ^2.4.0
```

Or install it via `flutter pub add`:

```bash
flutter pub add network_cache_interceptor
```

---

## 🚀 What’s New in Version 2.4.0

Version **2.4.0** adds encryption, offline-only reads, and finer caching control:

✅ **Optional AES Encryption at Rest:**
- Provide an `encryptionKey` (1-32 characters) to encrypt cached data (AES-GCM) and cache keys (deterministic AES-CBC) before they are stored in the local database.

✅ **`only_cache` Request Mode:**
- Serve a valid cached response or fail fast without hitting the network — ideal for instant offline reads.

✅ **`cacheWhen` Predicate:**
- Restrict which successful responses get cached with a simple callback (e.g. only cache bodies where `success == true`).

> The public API and import path are unchanged — everything from earlier versions keeps working.

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
      noCacheHttpMethods: ['POST', 'PUT'], // HTTP methods that should NOT be cached
      cacheValidityMinutes: 30,
      getCachedDataWhenError: true,
      uniqueWithHeader: true,
      encryptionKey: 'my_secret_key', // Optional: encrypt cache at rest (1-32 chars)
      cacheWhen: (response) =>          // Optional: only cache when this returns true
          response.data is Map && response.data['success'] == true,
    ),
  );
}
```

---

### 2. Make a Request

By default, **GET** requests are cached, unless explicitly disabled:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {
      'cache': true,         // Explicitly enable caching
      'validate_time': 60,   // Cache validity in minutes
    },
  ),
);
```

To **disable caching** for a request:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {'cache': false}, // Disable caching for this request
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
    extra: {
      'cache': true,
      'unique_key': 'user_123', // Cache entry specific to this key
    },
  ),
);
```

---

### 4. Offline-Only Reads with `only_cache`

Use `'only_cache'` to return cached data instantly and **skip the network entirely**. If no valid cache exists, the request fails fast with a `DioException` (`type: cancel`, `message: 'no_cache_available'`):

```dart
try {
  final response = await dio.get(
    'https://jsonplaceholder.typicode.com/posts',
    options: Options(extra: {'cache': 'only_cache'}),
  );
  print(response.data); // Served from cache, no network call
} on DioException catch (e) {
  if (e.message == 'no_cache_available') {
    print('No cached data available');
  }
}
```

---

### 5. Encrypt the Cache at Rest

Pass an `encryptionKey` (1-32 characters) to encrypt cached data and cache keys before they are written to the local database:

```dart
dio.interceptors.add(
  NetworkCacheInterceptor(encryptionKey: 'my_secret_key'),
);
```

Response bodies are encrypted with AES-GCM (random IV per entry) and cache keys with deterministic AES-CBC, so lookups stay consistent while data stays unreadable on disk.

---

### 6. Clear All Cached Data

To remove all cached data:

```dart
final cacheInterceptor = NetworkCacheInterceptor();
await cacheInterceptor.clearDatabase();
```

---

## ⚙️ Configuration

| Parameter                | Description                                                | Default Value          |
|--------------------------|------------------------------------------------------------|------------------------|
| `noCacheStatusCodes`     | HTTP status codes that should not be cached                | `[401, 403, 304]`      |
| `noCacheHttpMethods`     | HTTP methods (e.g., `POST`, `PUT`) that should not be cached| `['POST']`             |
| `cacheValidityMinutes`   | Cache validity duration (in minutes)                       | `30`                   |
| `getCachedDataWhenError` | Return cached data on network errors                       | `true`                 |
| `uniqueWithHeader`       | Use request headers for unique cache keys                  | `false`                |
| `cacheWhen`              | Predicate to restrict which responses get cached           | `null` (cache all)     |
| `encryptionKey`          | AES key (1-32 chars) to encrypt the cache at rest          | `null` (no encryption) |
| `unique_key`             | Custom key for precise cache separation                    | `''` (optional)        |

---

## 🔧 Technical Details

- **Offline Mode:** Cached responses are returned on timeouts, no connection, or socket errors.
- **Offline-Only Reads:** `only_cache` mode serves the cache and skips the network entirely.
- **Encryption at Rest:** Optional AES encryption for cached data (AES-GCM) and cache keys (AES-CBC).
- **Custom No-Cache HTTP Methods:** Control which request methods should bypass caching.
- **Custom Cache Filter:** Use `cacheWhen` to decide per response whether to cache it.
- **Header Filtering:** Ignores `Authorization`, `User-Agent`, and `content-length` headers in cache keys for consistency.
- **Granular Caching:** Supports `unique_key` and optional header-based differentiation.
- **Robust Database Handling:** Uses a local SQL database for efficient storage.

---

## 🎯 Example

```dart
final dio = Dio();
dio.interceptors.add(NetworkCacheInterceptor());

try {
  final response = await dio.get(
    'https://jsonplaceholder.typicode.com/posts',
    options: Options(
      extra: {'cache': true, 'unique_key': 'session_abc'},
    ),
  );
  print(response.data);
} catch (e) {
  print('Error: $e');
}
```

---

## 🛡️ License

This project is licensed under the [MIT](./LICENSE) License.

---

## 💬 Additional Information

For more information or to contribute, visit our GitHub page.

---

Stay tuned for more features and enhancements! 🎉

---

## 📦 Explore More

If you enjoy using this package, check out:

- **[Telegram Bot Crashlytics](https://pub.dev/packages/telegram_bot_crashlytics)** – Send app crashes and errors to a Telegram chat for easier monitoring.

---

Thanks for using **Network Cache Interceptor**! 🚀
