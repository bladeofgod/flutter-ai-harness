import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'computes validated Reward progress and immutable voucher summaries',
    () {
      final snapshot = RewardsSnapshot(
        balance: RewardBalance(availablePoints: 2450),
        progress: RewardProgress(
          currentTier: RewardTier.gold,
          nextTier: RewardTier.platinum,
          pointsEarned: 2450,
          pointsRequired: 3000,
        ),
        vouchers: <VoucherEntitlement>[
          VoucherEntitlement(
            voucher: Voucher(
              id: 'voucher-one',
              code: 'SAVE5',
              title: r'$5 off',
              discount: Money(currency: Currency.usd, minorUnits: 500),
              minimumSpend: Money(currency: Currency.usd, minorUnits: 1000),
            ),
            lifecycle: VoucherLifecycle.expiringSoon,
            expiresAt: DateTime.utc(2026, 7, 31),
          ),
        ],
      );

      expect(snapshot.progress.fraction, closeTo(2450 / 3000, 0.0001));
      expect(snapshot.progress.remainingPoints, 550);
      expect(snapshot.summary.usableVoucherCount, 1);
      expect(snapshot.summary.expiringVoucher?.voucher.id, 'voucher-one');
      expect(
        () => snapshot.vouchers.add(snapshot.vouchers.single),
        throwsUnsupportedError,
      );
    },
  );

  test('rejects invalid balances, progress, and duplicate voucher ids', () {
    expect(() => RewardBalance(availablePoints: -1), throwsArgumentError);
    expect(
      () => RewardProgress(
        currentTier: RewardTier.gold,
        nextTier: RewardTier.platinum,
        pointsEarned: 3100,
        pointsRequired: 3000,
      ),
      throwsArgumentError,
    );
    final entitlement = VoucherEntitlement(
      voucher: Voucher(
        id: 'duplicate',
        code: 'SAVE5',
        title: r'$5 off',
        discount: Money(currency: Currency.usd, minorUnits: 500),
        minimumSpend: Money(currency: Currency.usd, minorUnits: 1000),
      ),
      lifecycle: VoucherLifecycle.available,
      expiresAt: DateTime.utc(2026, 8, 1),
    );
    expect(
      () => RewardsSnapshot(
        balance: RewardBalance(availablePoints: 100),
        progress: RewardProgress(
          currentTier: RewardTier.silver,
          nextTier: RewardTier.gold,
          pointsEarned: 100,
          pointsRequired: 1000,
        ),
        vouchers: <VoucherEntitlement>[entitlement, entitlement],
      ),
      throwsArgumentError,
    );
  });
}
