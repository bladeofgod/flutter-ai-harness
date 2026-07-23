/// Wishlist 数据链路对 Feature 暴露的稳定失败类型。
final class WishlistFailure implements Exception {
  const WishlistFailure(this.code);

  final WishlistFailureCode code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WishlistFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'WishlistFailure(${code.name})';
}

enum WishlistFailureCode {
  unavailable,
  invalidRequest,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
