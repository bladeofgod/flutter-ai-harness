import 'package:app_data/rewards.dart';
import 'package:app_features/api/rewards_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rewards_test_fixtures.dart';

void main() {
  test('exposes a read-only Profile summary and reminder mutation', () async {
    final stack = TestRewardsStack();
    addTearDown(stack.dataSource.close);
    final RewardsApi api = stack.api;
    final emittedSummaries = <RewardSummary>[];
    final subscription = api.summaryUpdates.listen(emittedSummaries.add);
    addTearDown(subscription.cancel);

    final before = await api.loadSummary();
    final updated = await api.consumeReminder(
      voucherId: before.expiringVoucher!.voucher.id,
    );
    final rebuilt = await api.loadSummary();

    expect(before.usableVoucherCount, 1);
    expect(before.expiringVoucher?.voucher.id, 'voucher-shoppe-five');
    expect(updated.summary.expiringVoucher, isNull);
    expect(rebuilt.expiringVoucher, isNull);
    expect(emittedSummaries, hasLength(1));
    expect(emittedSummaries.single.expiringVoucher, isNull);
  });
}
