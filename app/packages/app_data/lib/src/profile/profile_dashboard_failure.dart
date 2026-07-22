/// Profile Dashboard 数据链路对 Feature 暴露的稳定失败类型。
final class ProfileDashboardFailure implements Exception {
  const ProfileDashboardFailure(this.code);

  final ProfileDashboardFailureCode code;

  @override
  String toString() => 'ProfileDashboardFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileDashboardFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum ProfileDashboardFailureCode {
  unavailable,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
