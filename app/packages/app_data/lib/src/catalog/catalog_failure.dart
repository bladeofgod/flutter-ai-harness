/// Catalog 数据链路对 Feature 暴露的稳定失败类型。
final class CatalogFailure implements Exception {
  const CatalogFailure(this.code);

  final CatalogFailureCode code;

  @override
  String toString() => 'CatalogFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CatalogFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum CatalogFailureCode {
  unavailable,
  notFound,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
