/// Stable infrastructure-level failure categories.
enum ApiFailureKind { unknownRequest, transport, invalidResponse, rejected }

/// A transport-neutral failure returned by [ApiClient].
final class ApiFailure {
  const ApiFailure._({
    required this.kind,
    required this.code,
    this.message,
    this.stackTrace,
  });

  const ApiFailure.unknownRequest({StackTrace? stackTrace})
    : this._(
        kind: ApiFailureKind.unknownRequest,
        code: 'unknown_request',
        stackTrace: stackTrace,
      );

  const ApiFailure.transport({StackTrace? stackTrace})
    : this._(
        kind: ApiFailureKind.transport,
        code: 'transport_error',
        stackTrace: stackTrace,
      );

  const ApiFailure.invalidResponse()
    : this._(kind: ApiFailureKind.invalidResponse, code: 'invalid_response');

  const ApiFailure.rejected({required String code, String? message})
    : this._(kind: ApiFailureKind.rejected, code: code, message: message);

  final ApiFailureKind kind;
  final String code;

  /// Optional consumer-facing context. Diagnostics intentionally omit it.
  final String? message;

  /// The original stack location when an exception was normalized.
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'ApiFailure(kind: ${kind.name}, code: $code, message: <redacted>)';
  }
}
