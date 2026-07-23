import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';
import '../fixture/fixture_api_transport.dart';
import '../fixture/shoppe_voucher_fixture.dart';

/// Rewards 请求键、固定进度与提醒消费状态的唯一所有者。
final class RewardsFixtureHandler implements FixtureRequestHandler {
  static const String loadKey = 'rewards.snapshot.load';
  static const String consumeReminderKey = 'rewards.reminder.consume';

  final Set<String> _consumedReminderIds = <String>{};

  void resetSession() => _consumedReminderIds.clear();

  @override
  Set<String> get requestKeys => const <String>{loadKey, consumeReminderKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadKey => ApiResponse<Object?>.success(_snapshotPayload()),
        consumeReminderKey => _consumeReminder(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _consumeReminder(Object? payload) {
    final voucherId = _map(payload)?['voucherId'];
    if (voucherId is! String || voucherId.isEmpty) {
      return _invalidInput();
    }
    final voucher = _voucherPayloads.firstWhere(
      (voucher) => voucher['id'] == voucherId,
      orElse: () => const <String, Object?>{},
    );
    if (voucher.isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'rewards.voucher_not_found'),
      );
    }
    if (voucher['lifecycle'] != 'expiring_soon' ||
        _consumedReminderIds.contains(voucherId)) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'rewards.reminder_unavailable'),
      );
    }
    final didMutate = _consumedReminderIds.add(voucherId);
    return ApiResponse<Object?>.success(<String, Object?>{
      'snapshot': _snapshotPayload(),
      'didMutate': didMutate,
    });
  }

  Map<String, Object?> _snapshotPayload() => <String, Object?>{
    'balance': <String, Object?>{'availablePoints': 2450},
    'progress': <String, Object?>{
      'currentTier': 'gold',
      'nextTier': 'platinum',
      'pointsEarned': 2450,
      'pointsRequired': 3000,
    },
    'vouchers': <Object?>[
      for (final voucher in _voucherPayloads)
        <String, Object?>{
          ...voucher,
          'reminderConsumed': _consumedReminderIds.contains(voucher['id']),
        },
    ],
  };

  static ApiResponse<Object?> _invalidInput() =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'rewards.invalid_input'),
      );
}

final List<Map<String, Object?>> _voucherPayloads = <Map<String, Object?>>[
  <String, Object?>{
    ..._voucherPayload(shoppeFiveVoucherFixture),
    'lifecycle': 'expiring_soon',
    'expiresAt': '2026-07-31T23:59:59.000Z',
  },
  <String, Object?>{
    'id': 'voucher-summer-ten',
    'code': 'SUMMER10',
    'title': r'$10 off selected Demo styles',
    'discount': <String, Object?>{'currency': 'USD', 'minorUnits': 1000},
    'minimumSpend': <String, Object?>{'currency': 'USD', 'minorUnits': 5000},
    'lifecycle': 'redeemed',
    'expiresAt': '2026-09-30T23:59:59.000Z',
  },
  <String, Object?>{
    'id': 'voucher-welcome-redeemed',
    'code': 'WELCOME5',
    'title': r'$5 welcome reward',
    'discount': <String, Object?>{'currency': 'USD', 'minorUnits': 500},
    'minimumSpend': <String, Object?>{'currency': 'USD', 'minorUnits': 500},
    'lifecycle': 'redeemed',
    'expiresAt': '2026-06-30T23:59:59.000Z',
  },
];

Map<String, Object?> _voucherPayload(Voucher voucher) => <String, Object?>{
  'id': voucher.id,
  'code': voucher.code,
  'title': voucher.title,
  'discount': _moneyPayload(voucher.discount),
  'minimumSpend': _moneyPayload(voucher.minimumSpend),
};

Map<String, Object?> _moneyPayload(Money money) => <String, Object?>{
  'currency': money.currency.code,
  'minorUnits': money.minorUnits,
};

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;
