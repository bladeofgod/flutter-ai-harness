import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/rewards_api.dart';
import 'package:app_features/feature_rewards/api/local_rewards_api.dart';

final class TestRewardsStack {
  TestRewardsStack()
    : dataSource = RewardsLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[RewardsFixtureHandler()],
          ),
        ),
      ) {
    api = LocalRewardsApi(dataSource: dataSource);
  }

  final RewardsLocalDataSource dataSource;
  late final LocalRewardsApi api;
}

final class FakeRewardsApi implements RewardsApi {
  FakeRewardsApi({required this.snapshot, this.failure, this.unexpectedError});

  RewardsSnapshot snapshot;
  RewardsFailure? failure;
  Object? unexpectedError;
  var loadCount = 0;
  var consumeCount = 0;
  final StreamController<RewardSummary> _summaryUpdates =
      StreamController<RewardSummary>.broadcast(sync: true);

  bool get hasSummaryListener => _summaryUpdates.hasListener;

  @override
  Stream<RewardSummary> get summaryUpdates => _summaryUpdates.stream;

  @override
  Future<RewardsSnapshot> load() async {
    loadCount += 1;
    final currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }
    final currentUnexpectedError = unexpectedError;
    if (currentUnexpectedError != null) {
      throw currentUnexpectedError;
    }
    return snapshot;
  }

  @override
  Future<RewardSummary> loadSummary() async => (await load()).summary;

  @override
  Future<RewardsSnapshot> consumeReminder({required String voucherId}) async {
    consumeCount += 1;
    final currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }
    final currentUnexpectedError = unexpectedError;
    if (currentUnexpectedError != null) {
      throw currentUnexpectedError;
    }
    snapshot = RewardsSnapshot(
      balance: snapshot.balance,
      progress: snapshot.progress,
      vouchers: <VoucherEntitlement>[
        for (final item in snapshot.vouchers)
          VoucherEntitlement(
            voucher: item.voucher,
            lifecycle: item.lifecycle,
            expiresAt: item.expiresAt,
            reminderConsumed:
                item.reminderConsumed || item.voucher.id == voucherId,
          ),
      ],
    );
    _summaryUpdates.add(snapshot.summary);
    return snapshot;
  }

  Future<void> close() => _summaryUpdates.close();
}

RewardsSnapshot testRewardsSnapshot({bool empty = false}) => RewardsSnapshot(
  balance: RewardBalance(availablePoints: 2450),
  progress: RewardProgress(
    currentTier: RewardTier.gold,
    nextTier: RewardTier.platinum,
    pointsEarned: 2450,
    pointsRequired: 3000,
  ),
  vouchers: empty
      ? const <VoucherEntitlement>[]
      : <VoucherEntitlement>[
          VoucherEntitlement(
            voucher: Voucher(
              id: 'voucher-shoppe-five',
              code: 'SHOPPE5',
              title: r'$5 off your Demo order',
              discount: Money(currency: Currency.usd, minorUnits: 500),
              minimumSpend: Money(currency: Currency.usd, minorUnits: 1000),
            ),
            lifecycle: VoucherLifecycle.expiringSoon,
            expiresAt: DateTime.utc(2026, 7, 31, 23, 59, 59),
          ),
          VoucherEntitlement(
            voucher: Voucher(
              id: 'voucher-used',
              code: 'USED5',
              title: r'$5 welcome reward',
              discount: Money(currency: Currency.usd, minorUnits: 500),
              minimumSpend: Money(currency: Currency.usd, minorUnits: 500),
            ),
            lifecycle: VoucherLifecycle.redeemed,
            expiresAt: DateTime.utc(2026, 6, 30),
          ),
        ],
);
