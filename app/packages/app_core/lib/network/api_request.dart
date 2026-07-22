/// A transport-neutral request with an opaque payload.
final class ApiRequest {
  const ApiRequest({required this.key, this.payload}) : assert(key != '');

  /// A stable key understood by the injected transport.
  final String key;

  /// Transport-specific data interpreted outside `app_core`.
  final Object? payload;

  @override
  String toString() => 'ApiRequest(key: $key, payload: <redacted>)';
}
