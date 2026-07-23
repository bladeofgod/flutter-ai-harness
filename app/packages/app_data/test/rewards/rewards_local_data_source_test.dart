import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('RewardsLocalDataSource', () {
    test('loads fixed balance, progress, dates, and Voucher Domain', () async {
      final source = _source(RewardsFixtureHandler());
      addTearDown(source.close);

      final snapshot = await source.load();

      expect(snapshot.balance.availablePoints, 2450);
      expect(snapshot.progress.currentTier, RewardTier.gold);
      expect(snapshot.progress.nextTier, RewardTier.platinum);
      expect(snapshot.progress.remainingPoints, 550);
      expect(snapshot.vouchers, hasLength(3));
      expect(snapshot.vouchers.first.voucher, isA<Voucher>());
      expect(snapshot.vouchers.first.voucher.id, 'voucher-shoppe-five');
      expect(snapshot.vouchers.first.voucher.code, 'SHOPPE5');
      expect(
        snapshot.vouchers.first.voucher.title,
        shoppeFiveVoucherFixture.title,
      );
      expect(
        snapshot.vouchers.first.voucher.discount,
        shoppeFiveVoucherFixture.discount,
      );
      expect(
        snapshot.vouchers.first.voucher.minimumSpend,
        shoppeFiveVoucherFixture.minimumSpend,
      );
      expect(
        snapshot.vouchers.first.expiresAt,
        DateTime.utc(2026, 7, 31, 23, 59, 59),
      );
      expect(snapshot.summary.expiringVoucher, isNotNull);
    });

    test('uses the same Voucher contract and values as Checkout', () async {
      final profileStore = PaymentProfileStore();
      final client = ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[
            RewardsFixtureHandler(),
            CheckoutFixtureHandler(paymentProfileStore: profileStore),
          ],
        ),
      );
      final rewards = RewardsLocalDataSource(apiClient: client);
      addTearDown(rewards.close);
      final checkout = CheckoutLocalDataSource(
        apiClient: client,
        paymentProfileStore: profileStore,
      );
      final subtotal = Money(currency: Currency.usd, minorUnits: 2000);

      final entitlement = (await rewards.load()).vouchers.first;
      final session = await checkout.applyVoucherById(
        voucherId: entitlement.voucher.id,
        subtotal: subtotal,
      );

      expect(session.voucher?.id, entitlement.voucher.id);
      expect(session.voucher?.discount, entitlement.voucher.discount);
      expect(session.voucher?.minimumSpend, entitlement.voucher.minimumSpend);
    });

    test('publishes a reminder once and rebuilds from handler state', () async {
      final handler = RewardsFixtureHandler();
      final source = _source(handler);
      addTearDown(source.close);
      final published = <RewardsSnapshot>[];
      final subscription = source.snapshotUpdates.listen(published.add);
      addTearDown(subscription.cancel);

      final first = await source.consumeReminder(
        voucherId: 'voucher-shoppe-five',
      );
      final rebuiltSource = _source(handler);
      addTearDown(rebuiltSource.close);

      expect(first.didMutate, isTrue);
      expect(first.snapshot.summary.expiringVoucher, isNull);
      expect(published, hasLength(1));
      expect(published.single.summary.expiringVoucher, isNull);
      expect((await rebuiltSource.load()).summary.expiringVoucher, isNull);
      expect((await _loadFreshRewards()).summary.expiringVoucher, isNotNull);
    });

    test('rejects consumed and non-expiring reminders consistently', () async {
      final source = _source(RewardsFixtureHandler());
      addTearDown(source.close);

      await source.consumeReminder(voucherId: 'voucher-shoppe-five');

      for (final voucherId in <String>[
        'voucher-shoppe-five',
        'voucher-summer-ten',
        'voucher-welcome-redeemed',
      ]) {
        await expectLater(
          source.consumeReminder(voucherId: voucherId),
          throwsA(const RewardsFailure(RewardsFailureCode.reminderUnavailable)),
        );
      }
    });

    test(
      'maps missing vouchers and malformed responses to stable failures',
      () async {
        await expectLater(
          _consumeMissingReminder(),
          throwsA(const RewardsFailure(RewardsFailureCode.voucherNotFound)),
        );
        final malformed = RewardsLocalDataSource(
          apiClient: const ApiClient(transport: _MalformedRewardsTransport()),
        );
        addTearDown(malformed.close);
        await expectLater(
          malformed.load(),
          throwsA(const RewardsFailure(RewardsFailureCode.invalidResponse)),
        );
      },
    );
  });
}

RewardsLocalDataSource _source(RewardsFixtureHandler handler) =>
    RewardsLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    );

Future<RewardsSnapshot> _loadFreshRewards() async {
  final source = _source(RewardsFixtureHandler());
  try {
    return await source.load();
  } finally {
    await source.close();
  }
}

Future<RewardsMutationResult> _consumeMissingReminder() async {
  final source = _source(RewardsFixtureHandler());
  try {
    return await source.consumeReminder(voucherId: 'missing');
  } finally {
    await source.close();
  }
}

final class _MalformedRewardsTransport implements ApiTransport {
  const _MalformedRewardsTransport();

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      const ApiResponse<Object?>.success(<String, Object?>{
        'balance': <String, Object?>{'availablePoints': 'many'},
        'progress': <String, Object?>{},
        'vouchers': <Object?>[],
      });
}
