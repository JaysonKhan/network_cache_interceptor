
# Changelog

## [2.4.0] - 2026-07-21

### Added
- **Optional AES encryption at rest:**
  - Pass an `encryptionKey` (1-32 characters) to encrypt cached data and cache keys before they are written to the local database. Response bodies use AES-GCM (random IV per entry); cache keys use deterministic AES-CBC so lookups stay consistent.
- **`only_cache` request mode:**
  - Set `extra: {'cache': 'only_cache'}` to serve a valid cached response or fail fast — without a network call — with a `DioException` (`type: cancel`, `message: 'no_cache_available'`).
- **`cacheWhen` predicate:**
  - An optional `bool Function(Response)` to further restrict which successful responses are cached (e.g. only cache bodies where `success == true`).

### Changed
- **Restructured into `lib/src/`:** the public API is exported from a single barrel file; internal helpers now live under `src/`. The public import path and API are unchanged.
- Cache keys now also ignore the `content-length` header for more consistent keys.

### Fixed
- Rewrote the test suite to run end-to-end against an in-memory SQLite database; all tests pass.

---

## [2.3.5] - Updated

### Added
- **No-Cache HTTP Methods Option:**
  - Developers can now specify HTTP methods (e.g., `POST`, `PUT`) that should **not** be cached, giving finer control over caching logic.

### Changed
- **Enhanced Offline Mode:**
  - Now leverages `DioExceptionType.connectionError` to detect offline scenarios and return cached data reliably.

### Fixed
- Improved handling of `unique_key` and request headers in cache key generation for consistent and reliable caching.

---

## [2.3.4] - Updated

### Changed
- **Caching Logic Improvement:**
  - `GET` requests are now cached **by default**, even if `cache: false` is explicitly specified.
  - Introduced `uniqueWithHeader` parameter to allow caching differentiation based on request headers.
  - Added better handling of `unique_key` for more precise cache invalidation.
  - `Authorization` and `User-Agent` headers are now ignored when generating cache keys to prevent unnecessary cache invalidation.

### Fixed
- Improved database synchronization to avoid data loss on unexpected crashes.
- Enhanced caching mechanism to reduce duplicate entries.
- Optimized cache key generation to ensure consistency and prevent mismatches.

---

## [1.2.4] - Updated

### Changed
- **Caching Logic Improvement:**
  - All `GET` requests are now cached **by default**, even if `cache: false` is explicitly specified.
  - Added more precise control through request `extra` parameters for cache behavior.

### Fixed
- Improved database synchronization to avoid data loss on unexpected crashes.
- Enhanced caching mechanism to reduce duplicate entries.

---

## [1.0.0] - Initial Release

### Added
- Introduced `NetworkCacheInterceptor` for caching Dio network requests.
- Added support for automatic caching and retrieval when offline.
- Included custom cache configuration:
  - `noCacheStatusCodes`: Prevents caching for specific status codes.
  - `cacheValidityMinutes`: Controls cache expiration time.
  - `getCachedDataWhenError`: Enables cache retrieval on network errors.
- Implemented local SQL-based storage for cached responses.
- Integrated error logging for easier debugging.

### Features
- Automatic request caching when enabled.
- Cache-based response retrieval if the network is unavailable.
- Customizable caching rules through extra request parameters.
- Database management methods like `clearDatabase()`.

---

## Future Improvements (Planned)
- Add support for custom cache storage engines.
- Include cache statistics and monitoring features.
- Expand request matching capabilities (query parameters and headers).
