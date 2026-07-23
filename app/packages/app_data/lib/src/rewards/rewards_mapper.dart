part of 'rewards_local.dart';

abstract final class _RewardsFixtureMapper {
  static RewardsSnapshot snapshot(Object? payload) => _decode(() {
    final values = _map(payload);
    final balance = _map(values['balance']);
    final progress = _map(values['progress']);
    final vouchers = values['vouchers'];
    if (vouchers is! List<Object?>) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return RewardsSnapshot(
      balance: RewardBalance(
        availablePoints: _integer(balance, 'availablePoints'),
      ),
      progress: RewardProgress(
        currentTier: _tier(_string(progress, 'currentTier')),
        nextTier: _tier(_string(progress, 'nextTier')),
        pointsEarned: _integer(progress, 'pointsEarned'),
        pointsRequired: _integer(progress, 'pointsRequired'),
      ),
      vouchers: vouchers.map(_voucher).toList(growable: false),
    );
  });

  static RewardsMutationResult mutation(Object? payload) => _decode(() {
    final values = _map(payload);
    final didMutate = values['didMutate'];
    if (didMutate is! bool) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return (snapshot: snapshot(values['snapshot']), didMutate: didMutate);
  });

  static VoucherEntitlement _voucher(Object? payload) {
    final values = _map(payload);
    return VoucherEntitlement(
      voucher: Voucher(
        id: _string(values, 'id'),
        code: _string(values, 'code'),
        title: _string(values, 'title'),
        discount: _money(values['discount']),
        minimumSpend: _money(values['minimumSpend']),
      ),
      lifecycle: switch (_string(values, 'lifecycle')) {
        'available' => VoucherLifecycle.available,
        'expiring_soon' => VoucherLifecycle.expiringSoon,
        'redeemed' => VoucherLifecycle.redeemed,
        'expired' => VoucherLifecycle.expired,
        _ => throw const RewardsFailure(RewardsFailureCode.invalidResponse),
      },
      expiresAt: DateTime.parse(_string(values, 'expiresAt')),
      reminderConsumed: _boolean(values, 'reminderConsumed'),
    );
  }

  static Money _money(Object? payload) {
    final values = _map(payload);
    return Money(
      currency: Currency.fromCode(_string(values, 'currency')),
      minorUnits: _integer(values, 'minorUnits'),
    );
  }

  static RewardTier _tier(String value) => switch (value) {
    'silver' => RewardTier.silver,
    'gold' => RewardTier.gold,
    'platinum' => RewardTier.platinum,
    _ => throw const RewardsFailure(RewardsFailureCode.invalidResponse),
  };

  static T _decode<T>(T Function() operation) {
    try {
      return operation();
    } on RewardsFailure {
      rethrow;
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const RewardsFailure(RewardsFailureCode.invalidResponse),
        stackTrace,
      );
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const RewardsFailure(RewardsFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return value;
  }

  static int _integer(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! int) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return value;
  }

  static bool _boolean(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! bool) {
      throw const RewardsFailure(RewardsFailureCode.invalidResponse);
    }
    return value;
  }
}
