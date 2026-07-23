/// Orders 数据链路对 Feature 暴露的稳定失败类型。
final class OrdersFailure implements Exception {
  const OrdersFailure(this.code);

  final OrdersFailureCode code;

  @override
  String toString() => 'OrdersFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OrdersFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum OrdersFailureCode {
  invalidInput,
  orderNotFound,
  alreadyReviewed,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
