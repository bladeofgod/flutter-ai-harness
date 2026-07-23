import 'package:app_features/api/rewards_api.dart';
import 'package:app_features/feature_profile/controllers/profile_rewards_summary_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../feature_rewards/rewards_test_fixtures.dart';

void main() {
  test('keeps a live summary subscription and releases it on close', () async {
    final api = FakeRewardsApi(snapshot: testRewardsSnapshot());
    addTearDown(api.close);
    final RewardsSummaryApi summaryApi = api;
    final controller = ProfileRewardsSummaryController(rewardsApi: summaryApi);

    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    expect(api.hasSummaryListener, isTrue);
    expect(
      (controller.state as ProfileRewardsSummaryData).summary.expiringVoucher,
      isNotNull,
    );

    await api.consumeReminder(voucherId: 'voucher-shoppe-five');

    expect(
      (controller.state as ProfileRewardsSummaryData).summary.expiringVoucher,
      isNull,
    );

    controller.onDelete();
    await Future<void>.delayed(Duration.zero);
    expect(api.hasSummaryListener, isFalse);
  });
}
