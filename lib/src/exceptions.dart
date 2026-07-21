/// Error attached to the [DioException] raised when a request in `only_cache`
/// mode finds no valid cached response.
///
/// The interceptor rejects such requests with a `DioException` whose `type` is
/// `DioExceptionType.cancel` and whose `error` is a [CacheMissException], so
/// applications can distinguish a cache miss from a real network/cancel error:
///
/// ```dart
/// try {
///   await dio.get('/data', options: Options(extra: {'cache': 'only_cache'}));
/// } on DioException catch (e) {
///   if (e.error is CacheMissException) {
///     // No cached data available for this request.
///   }
/// }
/// ```
class CacheMissException implements Exception {
  /// The path of the request that missed the cache.
  final String path;

  /// Creates a [CacheMissException] for the given request [path].
  const CacheMissException(this.path);

  @override
  String toString() => 'CacheMissException: no cached data for "$path"';
}
