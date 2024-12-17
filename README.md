
# Network Cache Interceptor

`Network Cache Interceptor` is a custom Dio interceptor designed for caching network requests. It returns cached data when offline and optimizes network request handling.

---

## 📦 Installation

Add the following line to your `pubspec.yaml`:

```yaml
dependencies:
  network_cache_interceptor: ^1.0.0
```

Or install it using `flutter pub add`:

```bash
flutter pub add network_cache_interceptor
```

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
      noCacheStatusCodes: [401, 403],
      cacheValidityMinutes: 30,
      getCachedDataWhenError: true,
    ),
  );
}
```

---

### 2. Make a Request

Add the `extra` parameter to enable caching:

```dart
final response = await dio.get(
  'https://jsonplaceholder.typicode.com/posts',
  options: Options(
    extra: {
      'cache': true,
      'validate_time': 60, // Cache validity time (minutes)
    },
  ),
);
```

---

### 3. Clear Cached Data

Clear all cached data from the database:

```dart
final cacheInterceptor = NetworkCacheInterceptor();
await cacheInterceptor.clearDatabase();
```

---

## ⚙️ Configuration

| Parameter                | Description                          | Default Value |
|-------------------------|--------------------------------------|----------------|
| `noCacheStatusCodes`     | Status codes not to be cached      | `[401, 403]`   |
| `cacheValidityMinutes`   | Cache validity time (minutes)      | `30`           |
| `getCachedDataWhenError` | Fetch cached data when offline     | `true`         |

---

## 🔧 Technical Details

- **Caching Logic:** If there's a network issue, previously cached responses are automatically returned if available.
- **Error Logging:** All errors are logged using `log()`.
- **Data Storage:** Data is saved locally using an SQL database.

---

## 🎯 Example

```dart
final dio = Dio();
dio.interceptors.add(NetworkCacheInterceptor());

try {
  final response = await dio.get(
    'https://jsonplaceholder.typicode.com/posts',
    options: Options(extra: {'cache': true}),
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
