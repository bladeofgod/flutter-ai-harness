/// Signals that a transport does not recognize a request key.
final class UnknownApiRequestException implements Exception {
  const UnknownApiRequestException(this.requestKey);

  final String requestKey;

  @override
  String toString() {
    return 'UnknownApiRequestException(requestKey: <redacted>)';
  }
}

/// Wraps a transport implementation error without exposing its cause in logs.
final class ApiTransportException implements Exception {
  const ApiTransportException({this.cause});

  /// Available for explicit inspection; never included in [toString].
  final Object? cause;

  @override
  String toString() => 'ApiTransportException(cause: <redacted>)';
}
