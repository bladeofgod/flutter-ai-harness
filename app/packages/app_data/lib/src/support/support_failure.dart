enum SupportFailureCode {
  invalidResponse,
  invalidState,
  questionNotFound,
  transportUnavailable,
  unknownRequest,
}

final class SupportFailure implements Exception {
  const SupportFailure(this.code);

  final SupportFailureCode code;

  @override
  String toString() => 'SupportFailure($code)';
}
