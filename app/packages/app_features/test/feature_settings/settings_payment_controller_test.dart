import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/settings_payment_api.dart';
import 'package:app_features/feature_settings/controllers/settings_payment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card input validates and never exposes sensitive fields', () {
    final input = PaymentCardInput(
      cardNumber: '4242 4242 4242 4242',
      cardholderName: 'Olivia Martin',
      expiry: '12/30',
      securityCode: '123',
    );

    expect(input.toString(), isNot(contains('4242 4242')));
    expect(input.toString(), isNot(contains('Olivia Martin')));
    expect(input.toString(), isNot(contains('12/30')));
    expect(input.toString(), isNot(contains('123')));
    expect(
      input.toPaymentMethod(id: 'payment-test').maskedLabel,
      'Visa •••• 4242',
    );
    expect(
      () => PaymentCardInput(
        cardNumber: '123456789012',
        cardholderName: 'Olivia Martin',
        expiry: '12/30',
        securityCode: '123',
      ),
      throwsFormatException,
    );
  });

  test('controller applies external checkout profile snapshots', () async {
    final api = _FakeSettingsPaymentApi();
    final controller = SettingsPaymentController(api: api);
    controller.onInit();
    addTearDown(controller.onDelete);
    await _waitUntil(() => controller.viewState is SettingsPaymentReady);

    final updated = ShippingAddress(
      id: 'shipping-office',
      recipientName: 'Olivia Martin',
      streetLine: '18 Market Street',
      city: 'San Francisco',
      region: 'CA',
      postalCode: '94105',
      country: 'United States',
    );
    api.publish(
      PaymentProfileSnapshot(
        addresses: <ShippingAddress>[...api.profile.addresses, updated],
        paymentMethods: api.profile.paymentMethods,
        selectedAddressId: updated.id,
        selectedPaymentMethodId: api.profile.selectedPaymentMethodId,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.overview!.paymentProfile.selectedAddressId, updated.id);
  });

  test('controller ignores duplicate card submits while mutating', () async {
    final api = _FakeSettingsPaymentApi(pauseMutations: true);
    final controller = SettingsPaymentController(api: api);
    controller.onInit();
    addTearDown(controller.onDelete);
    await _waitUntil(() => controller.viewState is SettingsPaymentReady);
    final input = PaymentCardInput(
      cardNumber: '4242424242424242',
      cardholderName: 'Olivia Martin',
      expiry: '12/30',
      securityCode: '123',
    );

    final first = controller.saveCard(input: input);
    final second = await controller.saveCard(input: input);
    expect(second, isFalse);
    api.completeMutation();
    expect(await first, isTrue);
    expect(api.upsertCalls, 1);
  });

  test('controller keeps a mutation failure visible until retry', () async {
    final api = _FakeSettingsPaymentApi(failAddressSelection: true);
    final controller = SettingsPaymentController(api: api);
    controller.onInit();
    addTearDown(controller.onDelete);
    await _waitUntil(() => controller.viewState is SettingsPaymentReady);

    expect(await controller.selectAddress('shipping-home'), isFalse);
    expect(controller.viewState, isA<SettingsPaymentError>());
  });

  test('controller releases its payment profile subscription', () async {
    final api = _FakeSettingsPaymentApi();
    final controller = SettingsPaymentController(api: api);
    controller.onInit();
    await _waitUntil(() => controller.viewState is SettingsPaymentReady);
    expect(api.hasProfileListener, isTrue);

    controller.onDelete();
    await Future<void>.delayed(Duration.zero);

    expect(api.hasProfileListener, isFalse);
  });
}

final class _FakeSettingsPaymentApi implements SettingsPaymentAddressApi {
  _FakeSettingsPaymentApi({
    this.pauseMutations = false,
    this.failAddressSelection = false,
  });

  final bool pauseMutations;
  final bool failAddressSelection;
  final StreamController<PaymentProfileSnapshot> _snapshots =
      StreamController<PaymentProfileSnapshot>.broadcast(sync: true);
  Completer<void>? _mutationCompleter;
  int upsertCalls = 0;
  PaymentProfileSnapshot profile = PaymentProfileStore().current;
  final List<CheckoutReceipt> receipts = <CheckoutReceipt>[];

  @override
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots =>
      _snapshots.stream;

  bool get hasProfileListener => _snapshots.hasListener;

  void publish(PaymentProfileSnapshot value) {
    profile = value;
    _snapshots.add(value);
  }

  void completeMutation() => _mutationCompleter?.complete();

  @override
  Future<SettingsPaymentOverview> load() async => _overview;

  @override
  Future<SettingsPaymentOverview> upsertPaymentMethod(
    PaymentMethod method,
  ) async {
    upsertCalls += 1;
    if (pauseMutations) {
      _mutationCompleter = Completer<void>();
      await _mutationCompleter!.future;
    }
    publish(
      PaymentProfileSnapshot(
        addresses: profile.addresses,
        paymentMethods: <PaymentMethod>[...profile.paymentMethods, method],
        selectedAddressId: profile.selectedAddressId,
        selectedPaymentMethodId: profile.selectedPaymentMethodId,
      ),
    );
    return _overview;
  }

  @override
  Future<SettingsPaymentOverview> removePaymentMethod(String methodId) =>
      throw UnimplementedError();

  @override
  Future<SettingsPaymentOverview> selectPaymentMethod(String methodId) =>
      throw UnimplementedError();

  @override
  Future<SettingsPaymentOverview> upsertAddress(ShippingAddress address) =>
      throw UnimplementedError();

  @override
  Future<SettingsPaymentOverview> removeAddress(String addressId) =>
      throw UnimplementedError();

  @override
  Future<SettingsPaymentOverview> selectAddress(String addressId) async {
    if (failAddressSelection) {
      throw const SettingsPaymentFailure(
        SettingsPaymentFailureCode.invalidInput,
      );
    }
    return _overview;
  }

  @override
  Future<SettingsPaymentOverview> recordReceipt(CheckoutReceipt receipt) =>
      throw UnimplementedError();

  SettingsPaymentOverview get _overview =>
      SettingsPaymentOverview(paymentProfile: profile, receipts: receipts);
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 20 && !predicate(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}
