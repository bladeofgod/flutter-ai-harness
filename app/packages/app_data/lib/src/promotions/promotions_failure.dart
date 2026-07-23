enum PromotionsFailureCode {
  unavailable,
  notFound,
  invalidResponse,
  unknownRequest,
  transportUnavailable,
}

final class PromotionsFailure implements Exception {
  const PromotionsFailure(this.code);

  final PromotionsFailureCode code;

  @override
  String toString() => 'PromotionsFailure(${code.name})';
}
