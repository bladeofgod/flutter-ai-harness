import '../checkout/checkout_models.dart';

enum RewardTier { silver, gold, platinum }

final class RewardBalance {
  factory RewardBalance({required int availablePoints}) {
    if (availablePoints < 0) {
      throw ArgumentError.value(
        availablePoints,
        'availablePoints',
        'Must not be negative.',
      );
    }
    return RewardBalance._(availablePoints);
  }

  const RewardBalance._(this.availablePoints);

  final int availablePoints;
}

final class RewardProgress {
  factory RewardProgress({
    required RewardTier currentTier,
    required RewardTier nextTier,
    required int pointsEarned,
    required int pointsRequired,
  }) {
    if (currentTier == nextTier) {
      throw ArgumentError('Current and next Reward tiers must differ.');
    }
    if (pointsEarned < 0 ||
        pointsRequired <= 0 ||
        pointsEarned > pointsRequired) {
      throw ArgumentError('Reward progress must fit its positive threshold.');
    }
    return RewardProgress._(
      currentTier: currentTier,
      nextTier: nextTier,
      pointsEarned: pointsEarned,
      pointsRequired: pointsRequired,
    );
  }

  const RewardProgress._({
    required this.currentTier,
    required this.nextTier,
    required this.pointsEarned,
    required this.pointsRequired,
  });

  final RewardTier currentTier;
  final RewardTier nextTier;
  final int pointsEarned;
  final int pointsRequired;

  double get fraction => pointsEarned / pointsRequired;
  int get remainingPoints => pointsRequired - pointsEarned;
}

enum VoucherLifecycle { available, expiringSoon, redeemed, expired }

/// 在公共 Checkout [Voucher] 上附加 Rewards 展示状态，不复制优惠规则。
final class VoucherEntitlement {
  factory VoucherEntitlement({
    required Voucher voucher,
    required VoucherLifecycle lifecycle,
    required DateTime expiresAt,
    bool reminderConsumed = false,
  }) => VoucherEntitlement._(
    voucher: voucher,
    lifecycle: lifecycle,
    expiresAt: expiresAt.toUtc(),
    reminderConsumed: reminderConsumed,
  );

  const VoucherEntitlement._({
    required this.voucher,
    required this.lifecycle,
    required this.expiresAt,
    required this.reminderConsumed,
  });

  final Voucher voucher;
  final VoucherLifecycle lifecycle;
  final DateTime expiresAt;
  final bool reminderConsumed;

  bool get isUsable =>
      lifecycle == VoucherLifecycle.available ||
      lifecycle == VoucherLifecycle.expiringSoon;
}

final class RewardSummary {
  const RewardSummary({
    required this.balance,
    required this.tier,
    required this.usableVoucherCount,
    required this.expiringVoucher,
  });

  final RewardBalance balance;
  final RewardTier tier;
  final int usableVoucherCount;
  final VoucherEntitlement? expiringVoucher;
}

final class RewardsSnapshot {
  factory RewardsSnapshot({
    required RewardBalance balance,
    required RewardProgress progress,
    required List<VoucherEntitlement> vouchers,
  }) {
    final ids = <String>{};
    for (final entitlement in vouchers) {
      if (!ids.add(entitlement.voucher.id)) {
        throw ArgumentError.value(vouchers, 'vouchers', 'Ids must be unique.');
      }
    }
    return RewardsSnapshot._(
      balance: balance,
      progress: progress,
      vouchers: List<VoucherEntitlement>.unmodifiable(vouchers),
    );
  }

  const RewardsSnapshot._({
    required this.balance,
    required this.progress,
    required this.vouchers,
  });

  final RewardBalance balance;
  final RewardProgress progress;
  final List<VoucherEntitlement> vouchers;

  RewardSummary get summary => RewardSummary(
    balance: balance,
    tier: progress.currentTier,
    usableVoucherCount: vouchers.where((item) => item.isUsable).length,
    expiringVoucher: _firstWhereOrNull(
      vouchers,
      (item) =>
          item.lifecycle == VoucherLifecycle.expiringSoon &&
          !item.reminderConsumed,
    ),
  );
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) matches) {
  for (final value in values) {
    if (matches(value)) {
      return value;
    }
  }
  return null;
}
