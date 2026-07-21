
# Changelog

## [3.0.0] - 2026-07-21

A major release focused on privacy-by-default, cache lifecycle control, and
observability.

### ⚠️ Breaking Changes
- **Opt-in storage by default (`storeOnlyOptIn: true`):** responses are now cached
  only when their request opts in (`extra['cache']` is set). Previously every
  eligible `GET` was written to disk. Set `storeOnlyOptIn: false` to restore the
  old behavior.
- **Opt-in offline fallback (`offlineFallbackOnlyOptIn: true`):** on connectivity
  errors, the cache is consulted only for opt-in requests. Set to `false` for the
  previous always-check behavior.
- **Configuration is applied once:** the first `NetworkCacheInterceptor(...)` call
  configures the singleton; later calls return the same instance and ignore their
  arguments (so `NetworkCacheInterceptor().clearDatabase()` no longer resets your
  options). Use `NetworkCacheInterceptor.instance` to access it.
- **Cache schema bumped to v3:** existing cached data is dropped on upgrade
  (the cache is disposable).

### Added
- **`'refresh'` request mode:** `extra: {'cache': 'refresh'}` always hits the
  network and stores the result without serving from cache — the revalidate leg
  of stale-while-revalidate.
- **`cachedThenFresh(dio, path)`:** a `Stream<Response>` that emits the cached
  response first (if any) and then the fresh network response.
- **Cache-hit markers:** served responses now carry `response.extra['from_cache']`
  (`true`) and `response.extra['cached_at']` (timestamp).
- **Original status code & headers preserved:** cache hits restore the stored
  status code and headers instead of a hardcoded `200`.
- **`CacheMissException`:** `only_cache` misses now reject with a `DioException`
  whose `error` is a `CacheMissException`, distinguishable from real errors.
- **Cache lifecycle API:** `invalidate(baseUrlWithPath)` clears all variants of an
  endpoint, `deleteExpired(maxAge)` prunes old entries, and `maxEntries` evicts the
  oldest entries once the cap is exceeded.
- **Encryption key rotation:** entries written under a previous key are detected
  and purged automatically instead of failing to decrypt.
- **`Duration` support:** `cacheValidity` (constructor) and `extra['validate_time']`
  now accept a `Duration` in addition to integer minutes.

### Notes
- Encrypting/decrypting very large payloads still runs on the main isolate;
  off-main-thread encryption is planned for a future release.

---

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
