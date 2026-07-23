import 'package:app_data/rewards.dart';

/// Profile 只消费 Rewards 摘要，不获得提醒 mutation 能力。
abstract interface class RewardsSummaryApi {
  Future<RewardSummary> loadSummary();

  Stream<RewardSummary> get summaryUpdates;
}

/// Rewards 页面消费的读取与提醒 mutation 边界。
abstract interface class RewardsApi implements RewardsSummaryApi {
  Future<RewardsSnapshot> load();

  Future<RewardsSnapshot> consumeReminder({required String voucherId});
}
