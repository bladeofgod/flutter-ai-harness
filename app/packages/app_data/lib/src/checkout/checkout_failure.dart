final class CheckoutFailure implements Exception {
  const CheckoutFailure(this.code);

  final CheckoutFailureCode code;

  @override
  String toString() => 'CheckoutFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      other is CheckoutFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

enum CheckoutFailureCode {
  invalidInput,
  invalidVoucher,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
