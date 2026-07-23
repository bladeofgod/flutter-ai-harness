import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('CheckoutLocalDataSource', () {
    test(
      'loads totals and applies or clears the deterministic voucher',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);

        var session = await fixture.source.load(subtotal: _subtotal);
        expect(session.total, _subtotal);
        expect(session.voucher, isNull);

        session = await fixture.source.applyVoucher(
          code: 'shoppe5',
          subtotal: _subtotal,
        );
        expect(session.voucher?.code, 'SHOPPE5');
        expect(session.discount.minorUnits, 500);
        expect(session.total.minorUnits, 2900);

        session = await fixture.source.clearVoucher(subtotal: _subtotal);
        expect(session.voucher, isNull);
        expect(session.total, _subtotal);
        session = await fixture.source.applyVoucherById(
          voucherId: 'voucher-shoppe-five',
          subtotal: _subtotal,
        );
        expect(session.voucher?.code, 'SHOPPE5');
        await expectLater(
          fixture.source.applyVoucherById(
            voucherId: 'voucher-unknown',
            subtotal: _subtotal,
          ),
          throwsA(const CheckoutFailure(CheckoutFailureCode.invalidVoucher)),
        );
        await expectLater(
          fixture.source.applyVoucher(code: 'NOPE', subtotal: _subtotal),
          throwsA(const CheckoutFailure(CheckoutFailureCode.invalidVoucher)),
        );
      },
    );

    test('reads external Store changes without a second copy', () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final adapter = _SettingsSideAdapter(fixture.store);
      final updated = ShippingAddress(
        id: 'shipping-home',
        recipientName: 'Settings Customer',
        streetLine: 'A deliberately long local address line',
        city: 'Hanoi',
        region: 'Ba Dinh',
        postalCode: '100000',
        country: 'Vietnam',
      );

      adapter.updateAddress(updated);
      final session = await fixture.source.load(subtotal: _subtotal);

      expect(
        session.paymentProfile.selectedAddress!.recipientName,
        updated.recipientName,
      );
      expect(
        session.paymentProfile.selectedAddress!.streetLine,
        updated.streetLine,
      );
      expect(
        fixture.source.currentPaymentProfile.selectedAddress,
        same(updated),
      );
      expect(
        PaymentProfileStore().current.selectedAddress!.recipientName,
        'Olivia Martin',
      );
    });

    test(
      'routes address and masked payment mutations through the Store',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        final office = ShippingAddress(
          id: 'shipping-office',
          recipientName: 'Demo Customer',
          streetLine: '100 Market Street',
          city: 'San Francisco',
          region: 'California',
          postalCode: '94105',
          country: 'United States',
        );
        final thirdCard = PaymentMethod(
          id: 'payment-card-third',
          brand: 'Visa',
          lastFour: '4567',
        );

        await fixture.source.upsertAddress(
          address: office,
          subtotal: _subtotal,
        );
        var session = await fixture.source.selectAddress(
          addressId: office.id,
          subtotal: _subtotal,
        );
        expect(session.paymentProfile.selectedAddress!.id, office.id);

        await fixture.source.upsertPaymentMethod(
          paymentMethod: thirdCard,
          subtotal: _subtotal,
        );
        session = await fixture.source.selectPaymentMethod(
          paymentMethodId: thirdCard.id,
          subtotal: _subtotal,
        );
        expect(session.paymentProfile.selectedPaymentMethod!.id, thirdCard.id);

        await fixture.source.removeAddress(
          addressId: office.id,
          subtotal: _subtotal,
        );
        session = await fixture.source.removePaymentMethod(
          paymentMethodId: thirdCard.id,
          subtotal: _subtotal,
        );
        expect(
          session.paymentProfile.addresses.any(
            (address) => address.id == office.id,
          ),
          isFalse,
        );
        expect(
          session.paymentProfile.paymentMethods.any(
            (method) => method.id == thirdCard.id,
          ),
          isFalse,
        );
      },
    );

    test(
      'maps primary success, secondary failure, and idempotent attempt',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        final primaryAttempt = await fixture.source.createPaymentAttempt();

        final first = await fixture.source.submitPayment(
          attemptId: primaryAttempt.id,
          amount: _subtotal,
        );
        final repeated = await fixture.source.submitPayment(
          attemptId: primaryAttempt.id,
          amount: _subtotal,
        );
        expect(first, isA<CheckoutPaymentSucceeded>());
        expect(
          (first as CheckoutPaymentSucceeded).receipt.id,
          (repeated as CheckoutPaymentSucceeded).receipt.id,
        );
        expect(first.receipt.amount, _subtotal);

        await fixture.source.selectPaymentMethod(
          paymentMethodId: 'payment-card-secondary',
          subtotal: _subtotal,
        );
        final secondaryAttempt = await fixture.source.createPaymentAttempt();
        expect(secondaryAttempt.id, isNot(primaryAttempt.id));
        final failed = await fixture.source.submitPayment(
          attemptId: secondaryAttempt.id,
          amount: _subtotal,
        );
        expect(
          failed,
          isA<CheckoutPaymentFailed>().having(
            (result) => result.reason,
            'reason',
            CheckoutPaymentFailureReason.paymentNotCompleted,
          ),
        );
      },
    );

    test('maps malformed payloads and invalid attempt reuse', () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final attempt = await fixture.source.createPaymentAttempt();
      await fixture.source.submitPayment(
        attemptId: attempt.id,
        amount: _subtotal,
      );
      await expectLater(
        fixture.source.submitPayment(
          attemptId: attempt.id,
          amount: Money(currency: Currency.usd, minorUnits: 3500),
        ),
        throwsA(const CheckoutFailure(CheckoutFailureCode.invalidInput)),
      );

      final malformed = CheckoutLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: const <FixtureRequestHandler>[
              _MalformedCheckoutHandler(),
            ],
          ),
        ),
        paymentProfileStore: PaymentProfileStore(),
      );
      await expectLater(
        malformed.load(subtotal: _subtotal),
        throwsA(const CheckoutFailure(CheckoutFailureCode.invalidResponse)),
      );
    });
  });
}

final Money _subtotal = Money(currency: Currency.usd, minorUnits: 3400);

final class _Fixture {
  _Fixture() {
    handler = CheckoutFixtureHandler(
      paymentProfileStore: store,
      paymentDelay: Duration.zero,
    );
    source = CheckoutLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
      paymentProfileStore: store,
    );
  }

  final PaymentProfileStore store = PaymentProfileStore();
  late final CheckoutFixtureHandler handler;
  late final CheckoutLocalDataSource source;

  Future<void> close() => store.close();
}

final class _SettingsSideAdapter {
  const _SettingsSideAdapter(this.store);

  final PaymentProfileStore store;

  void updateAddress(ShippingAddress address) => store.upsertAddress(address);
}

final class _MalformedCheckoutHandler implements FixtureRequestHandler {
  const _MalformedCheckoutHandler();

  @override
  Set<String> get requestKeys => const <String>{CheckoutFixtureHandler.loadKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      const ApiResponse<Object?>.success(<String, Object?>{
        'subtotal': 'invalid',
      });
}
