import 'package:app_data/rewards.dart';

import '../../api/rewards_api.dart';

final class LocalRewardsApi implements RewardsApi {
  const LocalRewardsApi({required RewardsLocalDataSource dataSource})
    : _dataSource = dataSource;

  final RewardsLocalDataSource _dataSource;

  @override
  Stream<RewardSummary> get summaryUpdates =>
      _dataSource.snapshotUpdates.map((snapshot) => snapshot.summary);

  @override
  Future<RewardsSnapshot> load() => _dataSource.load();

  @override
  Future<RewardSummary> loadSummary() async =>
      (await _dataSource.load()).summary;

  @override
  Future<RewardsSnapshot> consumeReminder({required String voucherId}) async =>
      (await _dataSource.consumeReminder(voucherId: voucherId)).snapshot;
}
