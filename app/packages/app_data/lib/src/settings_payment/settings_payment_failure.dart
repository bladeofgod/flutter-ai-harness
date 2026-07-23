enum SettingsPaymentFailureCode {
  invalidInput,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}

final class SettingsPaymentFailure implements Exception {
  const SettingsPaymentFailure(this.code);

  final SettingsPaymentFailureCode code;

  @override
  String toString() => 'SettingsPaymentFailure(code: ${code.name})';
}
