import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('SettingsPaymentLocalDataSource', () {
    late _Fixture fixture;

    setUp(() => fixture = _Fixture());
    tearDown(() => fixture.close());

    test('shares one profile store with checkout and publishes once', () async {
      final snapshots = <PaymentProfileSnapshot>[];
      final subscription = fixture.checkout.paymentProfileSnapshots.listen(
        snapshots.add,
      );
      addTearDown(subscription.cancel);

      final office = ShippingAddress(
        id: 'shipping-office',
        recipientName: 'Olivia Martin',
        streetLine: '18 Market Street',
        city: 'San Francisco',
        region: 'CA',
        postalCode: '94105',
        country: 'United States',
      );
      final overview = await fixture.settings.upsertAddress(office);

      expect(snapshots, hasLength(1));
      expect(snapshots.single.addresses.last.id, office.id);
      expect(overview.paymentProfile.addresses.last.id, office.id);
      final checkout = await fixture.checkout.load(
        subtotal: Money(currency: Currency.usd, minorUnits: 4200),
      );
      expect(checkout.paymentProfile.addresses.last.id, office.id);
    });

    test('card mutations stay masked and snapshots are immutable', () async {
      final added = await fixture.settings.upsertPaymentMethod(
        PaymentMethod(
          id: 'payment-card-settings-1',
          brand: 'Visa',
          lastFour: '4242',
        ),
      );
      expect(
        added.paymentProfile.paymentMethods.last.maskedLabel,
        'Visa •••• 4242',
      );
      expect(
        added.paymentProfile.paymentMethods.last.toString(),
        contains('<redacted>'),
      );
      expect(
        () => added.paymentProfile.paymentMethods.add(
          PaymentMethod(id: 'other', brand: 'Card', lastFour: '1111'),
        ),
        throwsUnsupportedError,
      );

      final selected = await fixture.settings.selectPaymentMethod(
        'payment-card-settings-1',
      );
      expect(
        selected.paymentProfile.selectedPaymentMethodId,
        'payment-card-settings-1',
      );
      final removed = await fixture.settings.removePaymentMethod(
        'payment-card-settings-1',
      );
      expect(
        removed.paymentProfile.paymentMethods,
        isNot(
          contains(
            isA<PaymentMethod>().having(
              (method) => method.id,
              'id',
              'payment-card-settings-1',
            ),
          ),
        ),
      );
    });

    test('a Settings-created Demo card completes Checkout', () async {
      final method = PaymentMethod(
        id: 'payment-card-settings-1',
        brand: 'Visa',
        lastFour: '4242',
      );
      await fixture.settings.upsertPaymentMethod(method);
      await fixture.settings.selectPaymentMethod(method.id);

      final attempt = await fixture.checkout.createPaymentAttempt();
      final result = await fixture.checkout.submitPayment(
        attemptId: attempt.id,
        amount: Money(currency: Currency.usd, minorUnits: 4200),
      );

      expect(result, isA<CheckoutPaymentSucceeded>());
      expect(
        (result as CheckoutPaymentSucceeded).receipt.paymentMethodId,
        method.id,
      );
      expect(result.receipt.maskedPaymentLabel, method.maskedLabel);
    });

    test('records only supplied checkout receipts and is idempotent', () async {
      expect((await fixture.settings.load()).receipts, isEmpty);
      final receipt = _receipt();

      await fixture.settings.recordReceipt(receipt);
      final overview = await fixture.settings.recordReceipt(receipt);

      expect(overview.receipts, hasLength(1));
      expect(overview.receipts.single.id, receipt.id);
      expect(overview.receipts.single.maskedPaymentLabel, 'Visa •••• 9843');
      expect(() => overview.receipts.add(receipt), throwsUnsupportedError);
    });

    test(
      'a new fixture restores the fixed profile and empty history',
      () async {
        await fixture.settings.removeAddress('shipping-home');
        await fixture.settings.recordReceipt(_receipt());

        final rebuilt = _Fixture();
        addTearDown(rebuilt.close);
        final overview = await rebuilt.settings.load();

        expect(overview.paymentProfile.selectedAddressId, 'shipping-home');
        expect(overview.paymentProfile.addresses, hasLength(1));
        expect(overview.receipts, isEmpty);
      },
    );

    test('maps rejected mutations to a settings failure', () async {
      await expectLater(
        fixture.settings.removeAddress('missing-address'),
        throwsA(
          isA<SettingsPaymentFailure>().having(
            (failure) => failure.code,
            'code',
            SettingsPaymentFailureCode.invalidInput,
          ),
        ),
      );
    });

    test('rejects malformed receipt payload before storing it', () async {
      final handler = SettingsPaymentFixtureHandler(
        paymentProfileStore: fixture.store,
      );
      final response = await handler.handle(
        const ApiRequest(
          key: SettingsPaymentFixtureHandler.recordReceiptKey,
          payload: <String, Object?>{
            'receipt': <String, Object?>{'id': 'incomplete-receipt'},
          },
        ),
      );

      expect(response, isA<ApiError<Object?>>());
    });

    test('maps malformed success payloads to invalidResponse', () async {
      for (final payload in <Object?>[
        const <String, Object?>{},
        _overviewPayload(
          paymentMethods: const <Object?>[
            <String, Object?>{
              'id': 'payment-invalid',
              'brand': 'Visa',
              'lastFour': '42',
            },
          ],
        ),
        _overviewPayload(
          receipts: <Object?>[
            <String, Object?>{
              'id': 'receipt-invalid',
              'attemptId': 'attempt-invalid',
              'amount': <String, Object?>{
                'currency': 'USD',
                'minorUnits': 4200,
              },
              'paymentMethodId': 'payment-card-primary',
              'maskedPaymentLabel': 'Visa masked',
              'shippingAddress': _addressPayload,
              'issuedAt': 'not-a-date',
            },
          ],
        ),
      ]) {
        final store = PaymentProfileStore();
        final source = SettingsPaymentLocalDataSource(
          apiClient: ApiClient(
            transport: FixtureApiTransport(
              handlers: <FixtureRequestHandler>[
                _MalformedSettingsPaymentHandler(payload),
              ],
            ),
          ),
          paymentProfileStore: store,
        );

        await expectLater(
          source.load(),
          throwsA(
            isA<SettingsPaymentFailure>().having(
              (failure) => failure.code,
              'code',
              SettingsPaymentFailureCode.invalidResponse,
            ),
          ),
        );
        await store.close();
      }
    });
  });
}

Map<String, Object?> _overviewPayload({
  List<Object?> paymentMethods = const <Object?>[],
  List<Object?> receipts = const <Object?>[],
}) => <String, Object?>{
  'paymentProfile': <String, Object?>{
    'addresses': const <Object?>[_addressPayload],
    'paymentMethods': paymentMethods,
    'selectedAddressId': 'shipping-home',
    'selectedPaymentMethodId': null,
  },
  'receipts': receipts,
};

const Map<String, Object?> _addressPayload = <String, Object?>{
  'id': 'shipping-home',
  'recipientName': 'Olivia Martin',
  'streetLine': '26 Demo Street',
  'city': 'Ho Chi Minh City',
  'region': 'District 2',
  'postalCode': '700000',
  'country': 'Vietnam',
};

final class _MalformedSettingsPaymentHandler implements FixtureRequestHandler {
  const _MalformedSettingsPaymentHandler(this.payload);

  final Object? payload;

  @override
  Set<String> get requestKeys => const <String>{
    SettingsPaymentFixtureHandler.loadKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _Fixture {
  _Fixture() {
    final transport = FixtureApiTransport(
      handlers: <FixtureRequestHandler>[
        CheckoutFixtureHandler(
          paymentProfileStore: store,
          paymentDelay: Duration.zero,
        ),
        SettingsPaymentFixtureHandler(paymentProfileStore: store),
      ],
    );
    final client = ApiClient(transport: transport);
    settings = SettingsPaymentLocalDataSource(
      apiClient: client,
      paymentProfileStore: store,
    );
    checkout = CheckoutLocalDataSource(
      apiClient: client,
      paymentProfileStore: store,
    );
  }

  final PaymentProfileStore store = PaymentProfileStore();
  late final SettingsPaymentLocalDataSource settings;
  late final CheckoutLocalDataSource checkout;

  Future<void> close() => store.close();
}

CheckoutReceipt _receipt() => CheckoutReceipt(
  id: 'receipt-settings-test',
  attemptId: 'attempt-settings-test',
  amount: Money(currency: Currency.usd, minorUnits: 4200),
  paymentMethodId: 'payment-card-primary',
  maskedPaymentLabel: 'Visa •••• 9843',
  shippingAddress: ShippingAddress(
    id: 'shipping-home',
    recipientName: 'Olivia Martin',
    streetLine: '26 Demo Street',
    city: 'Ho Chi Minh City',
    region: 'District 2',
    postalCode: '700000',
    country: 'Vietnam',
  ),
  issuedAt: DateTime.utc(2026, 7, 22, 8),
);
