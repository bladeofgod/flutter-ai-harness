import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('fixture snapshots are immutable and a new store restores defaults', () {
    final first = PaymentProfileStore();
    final originalAddress = first.current.selectedAddress!;

    expect(
      () => first.current.addresses.add(originalAddress),
      throwsUnsupportedError,
    );
    first.upsertAddress(
      ShippingAddress(
        id: originalAddress.id,
        recipientName: 'Updated Name',
        streetLine: originalAddress.streetLine,
        city: originalAddress.city,
        region: originalAddress.region,
        postalCode: originalAddress.postalCode,
        country: originalAddress.country,
      ),
    );

    expect(first.current.selectedAddress!.recipientName, 'Updated Name');
    expect(
      PaymentProfileStore().current.selectedAddress!.recipientName,
      'Olivia Martin',
    );
  });

  test('each successful mutation emits one consistent snapshot', () async {
    final store = PaymentProfileStore();
    addTearDown(store.close);
    final snapshots = <PaymentProfileSnapshot>[];
    final subscription = store.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);

    final secondAddress = ShippingAddress(
      id: 'shipping-office',
      recipientName: 'Demo Customer',
      streetLine: '100 Market Street',
      city: 'San Francisco',
      region: 'California',
      postalCode: '94105',
      country: 'United States',
    );
    store.upsertAddress(secondAddress);
    store.selectAddress(secondAddress.id);
    store.upsertPaymentMethod(
      PaymentMethod(id: 'payment-card-third', brand: 'Visa', lastFour: '4567'),
    );
    store.selectPaymentMethod('payment-card-third');
    store.removeAddress(secondAddress.id);
    store.removePaymentMethod('payment-card-third');

    expect(snapshots, hasLength(6));
    expect(snapshots[1].selectedAddressId, secondAddress.id);
    expect(snapshots[3].selectedPaymentMethodId, 'payment-card-third');
    expect(snapshots.last.selectedPaymentMethodId, 'payment-card-primary');
  });

  test('payment diagnostics never expand card data', () {
    final method = PaymentMethod(
      id: 'payment-demo',
      brand: 'Visa',
      lastFour: '4242',
    );
    final address = PaymentProfileStore().current.selectedAddress!;
    final receipt = CheckoutReceipt(
      id: 'receipt-demo',
      attemptId: 'attempt-demo',
      amount: Money(currency: Currency.usd, minorUnits: 3400),
      paymentMethodId: method.id,
      maskedPaymentLabel: method.maskedLabel,
      shippingAddress: address,
      issuedAt: DateTime.utc(2026, 7, 22),
    );

    expect(method.toString(), contains('<redacted>'));
    expect(method.toString(), isNot(contains('4242')));
    expect(receipt.toString(), contains('<redacted>'));
    expect(receipt.toString(), isNot(contains('4242')));
    expect(address.toString(), contains('<redacted>'));
    expect(address.toString(), isNot(contains(address.streetLine)));
  });

  test('rejects unmasked cards and invalid selected IDs', () {
    expect(
      () => PaymentMethod(
        id: 'payment-card',
        brand: 'Visa',
        lastFour: '4242424242424242',
      ),
      throwsArgumentError,
    );
    expect(
      () => PaymentProfileSnapshot(
        addresses: const <ShippingAddress>[],
        paymentMethods: const <PaymentMethod>[],
        selectedAddressId: 'missing',
        selectedPaymentMethodId: null,
      ),
      throwsArgumentError,
    );
  });
}
