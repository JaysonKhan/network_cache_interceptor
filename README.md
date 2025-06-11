
# Network Cache Interceptor

`Network Cache Interceptor` is a custom Dio interceptor for caching network requests. It delivers cached data when offline and improves network request handling.

---

## 📦 Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  network_cache_interceptor: ^2.3.5
```

Or install it via `flutter pub add`:

```bash
flutter pub add network_cache_interceptor
```

---

## 🚀 What’s New in Version 2.3.5

Version **2.3.5** brings improved caching behavior and greater developer control:

✅ **New Features:**
- **No-Cache HTTP Methods Option:**  
  You can now specify which HTTP methods should **not** be cached (e.g., `POST`, `PUT`). This is similar to `noCacheStatusCodes` and gives developers finer control.

✅ **Enhanced Offline Mode:**
- Now uses `DioExceptionType.connectionError` to better detect offline situations and return cached data when appropriate.

✅ **Improved Robustness:**
- Improved handling of `unique_key` and headers when generating cache keys.

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
      noCacheHttpMethods: ['POST', 'PUT'], // Specify which HTTP methods should NOT be cached
      cacheValidityMinutes: 30,
      getCachedDataWhenError: true,
      uniqueWithHeader: true,
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

### 4. Clear All Cached Data

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
| `unique_key`             | Custom key for precise cache separation                    | `''` (optional)        |

---

## 🔧 Technical Details

- **Offline Mode:** Cached responses are returned on timeouts, no connection, or socket errors.
- **Custom No-Cache HTTP Methods:** Control which request methods should bypass caching.
- **Header Filtering:** Ignores `Authorization` and `User-Agent` headers in cache keys for consistency.
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
