/// Rewards 数据链路对 Feature 暴露的稳定失败类型。
final class RewardsFailure implements Exception {
  const RewardsFailure(this.code);

  final RewardsFailureCode code;

  @override
  String toString() => 'RewardsFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RewardsFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum RewardsFailureCode {
  invalidInput,
  voucherNotFound,
  reminderUnavailable,
  unexpected,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}
