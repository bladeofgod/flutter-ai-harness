import 'package:app_data/rewards.dart';
import 'package:app_features/feature_rewards/controllers/rewards_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rewards_test_fixtures.dart';

void main() {
  test('loads, selects, and submits a reminder only once in flight', () async {
    final api = FakeRewardsApi(snapshot: testRewardsSnapshot());
    addTearDown(api.close);
    final controller = RewardsController(rewardsApi: api);
    addTearDown(controller.onDelete);

    await controller.load();
    expect(controller.viewState, isA<RewardsData>());

    controller.selectVoucher('voucher-shoppe-five');
    expect(controller.selectedVoucherId, 'voucher-shoppe-five');
    controller.selectVoucher('voucher-shoppe-five');
    expect(controller.selectedVoucherId, isNull);
    controller.selectVoucher('missing');
    expect(controller.selectedVoucherId, isNull);

    controller.consumeReminderFromUi('voucher-shoppe-five');
    controller.consumeReminderFromUi('voucher-shoppe-five');
    await Future<void>.delayed(Duration.zero);

    expect(api.consumeCount, 1);
    final snapshot = (controller.viewState as RewardsData).snapshot;
    expect(snapshot.summary.expiringVoucher, isNull);
  });

  test('represents empty and retryable error states', () async {
    final api = FakeRewardsApi(
      snapshot: testRewardsSnapshot(empty: true),
      failure: const RewardsFailure(RewardsFailureCode.transportUnavailable),
    );
    addTearDown(api.close);
    final controller = RewardsController(rewardsApi: api);
    addTearDown(controller.onDelete);

    await controller.load();
    expect(controller.viewState, isA<RewardsError>());

    api.failure = null;
    await controller.load();
    expect(controller.viewState, isA<RewardsEmpty>());
  });

  test('maps unexpected load errors to a retryable error state', () async {
    final api = FakeRewardsApi(
      snapshot: testRewardsSnapshot(),
      unexpectedError: StateError('fixture failed'),
    );
    addTearDown(api.close);
    final controller = RewardsController(rewardsApi: api);
    addTearDown(controller.onDelete);
    final previousOnError = FlutterError.onError;
    final reportedErrors = <FlutterErrorDetails>[];
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    await controller.load();

    final state = controller.viewState as RewardsError;
    expect(state.failure.code, RewardsFailureCode.unexpected);
    expect(reportedErrors, hasLength(1));

    api.unexpectedError = null;
    await controller.load();
    expect(controller.viewState, isA<RewardsData>());
  });
}
