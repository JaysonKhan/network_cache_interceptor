
# Network Cache Interceptor

`Network Cache Interceptor` is a custom Dio interceptor designed for caching network requests. It returns cached data when offline and optimizes network request handling.

---

## 📦 Installation

Add the following line to your `pubspec.yaml`:

```yaml
dependencies:
  network_cache_interceptor: ^2.3.4
```

Or install it using `flutter pub add`:

```bash
flutter pub add network_cache_interceptor
```

---

## 🚀 What’s New in Version 2.3.4

- **Enhanced Caching Logic:**  
  In version **2.3.4**, caching has been improved with the following updates:
  - `GET` requests are now cached **by default**, even if `cache: false` is explicitly specified.
  - Introduced `uniqueWithHeader` parameter, allowing differentiation based on request headers.
  - Introduced `unique_key` parameter for more precise cache invalidation per request.
  - `Authorization` and `User-Agent` headers are now ignored when generating cache keys to prevent unnecessary cache invalidation.
  - Improved `unique_key` handling for better cache management.

---

## 🚀 Usage

### 1. Configure `Dio`

```dart
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';

void main() {
  final dio = Dio();

  // Attach the interceptor
  dio.interceptors.add(
    NetworkCacheInterceptor(
      noCacheStatusCodes: [401, 403, 304],
      cacheValidityMinutes: 30,
      getCachedDataWhenError: true,
      uniqueWithHeader: true,
    ),
  );
}
```

---

### 2. Make a Request

All **GET** requests are now cached by default, but you can still override caching behavior using `extra['cache']`:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {
      'cache': true,         // Explicitly enable caching
      'validate_time': 60,   // Cache validity time (minutes)
    },
  ),
);
```

To **disable caching manually**:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {'cache': false}, // Disable caching
  ),
);
```

---

### 3. Using `unique_key` for More Precise Cache Invalidation

The `unique_key` parameter allows more precise control over cache storage and retrieval.  
It is useful when the same request may return different results based on dynamic parameters.

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {
      'cache': true, 
      'unique_key': 'user_123', // Ensures this request gets a unique cache key
    },
  ),
);
```

This ensures that responses are cached separately for different `unique_key` values.

---

### 4. Clear Cached Data

Clear all cached data from the database:

```dart
final cacheInterceptor = NetworkCacheInterceptor();
await cacheInterceptor.clearDatabase();
```

---

## ⚙️ Configuration

| Parameter                | Description                                    | Default Value |
|-------------------------|------------------------------------------------|---------------|
| `noCacheStatusCodes`     | Status codes that should not be cached        | `[401, 403, 304]` |
| `cacheValidityMinutes`   | Cache validity duration (in minutes)          | `30`           |
| `getCachedDataWhenError` | Fetch cached data when offline                | `true`         |
| `uniqueWithHeader`       | Differentiates cache keys based on headers    | `false`        |
| `unique_key`             | Custom key to uniquely store/retrieve cache   | `''` (optional) |

---

## 🔧 Technical Details

- **Caching Logic:** If there's a network issue, previously cached responses are automatically returned if available.
- **Header Filtering:** `Authorization` and `User-Agent` headers are ignored when generating cache keys.
- **`unique_key` Support:** Allows more granular cache control by separating responses.
- **Improved Error Handling:** Better handling of network failures with enhanced logging.
- **Data Storage:** Cached data is stored locally using an SQL database.

---

## 🎯 Example

```dart
final dio = Dio();
dio.interceptors.add(NetworkCacheInterceptor());

try {
final response = await dio.get(
'https://jsonplaceholder.typicode.com/posts',
options: Options(extra: {'cache': true, 'unique_key': 'session_abc'}),
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

Stay updated on new releases and project announcements! 🎉

---

## 📦 Check Out My Other Packages

If you find this package useful, you might also be interested in:

- **[Telegram Bot Crashlytics](https://pub.dev/packages/telegram_bot_crashlytics)** - A comprehensive error logging package that sends application crashes and errors directly to a Telegram chat.

Stay connected for more powerful and easy-to-use packages! 🚀
