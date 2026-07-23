/// Cart 数据链路对 Feature 暴露的稳定失败类型。
final class CartFailure implements Exception {
  const CartFailure(this.code);

  final CartFailureCode code;

  @override
  String toString() => 'CartFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CartFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum CartFailureCode {
  invalidInput,
  lineNotFound,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
