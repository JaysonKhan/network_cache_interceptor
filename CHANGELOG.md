
# Changelog

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

