import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/feature_checkout/api/local_checkout_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards one Store snapshot for a successful API mutation', () async {
    final store = PaymentProfileStore();
    addTearDown(store.close);
    final api = LocalCheckoutApi(
      dataSource: CheckoutLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[
              CheckoutFixtureHandler(
                paymentProfileStore: store,
                paymentDelay: Duration.zero,
              ),
            ],
          ),
        ),
        paymentProfileStore: store,
      ),
    );
    final snapshots = <PaymentProfileSnapshot>[];
    final subscription = api.paymentProfileSnapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    final address = ShippingAddress(
      id: 'shipping-office',
      recipientName: 'Demo Customer',
      streetLine: '100 Market Street',
      city: 'San Francisco',
      region: 'California',
      postalCode: '94105',
      country: 'United States',
    );

    final session = await api.upsertAddress(
      address: address,
      subtotal: Money(currency: Currency.usd, minorUnits: 3400),
    );

    expect(snapshots, hasLength(1));
    expect(session.paymentProfile.addresses.last.id, address.id);
    expect(store.current.addresses.last.id, address.id);
  });
}
