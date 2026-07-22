/// Auth 数据链路对 Feature 暴露的稳定失败类型。
final class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;

  @override
  String toString() => 'AuthFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuthFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// 不依赖传输实现的 Auth 失败码。
enum AuthFailureCode {
  accountNotFound,
  duplicateAccount,
  invalidCredentials,
  invalidRequest,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
