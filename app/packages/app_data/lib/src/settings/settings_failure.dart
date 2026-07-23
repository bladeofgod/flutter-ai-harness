/// Settings 数据链路对 Feature 暴露的稳定失败类型。
final class SettingsFailure implements Exception {
  const SettingsFailure(this.code);

  final SettingsFailureCode code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SettingsFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'SettingsFailure(${code.name})';
}

enum SettingsFailureCode {
  unavailable,
  invalidRequest,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
