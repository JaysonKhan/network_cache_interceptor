
# Changelog

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
