import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_checkout/controllers/checkout_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'checkout_test_fixtures.dart';

void main() {
  test('loads a non-empty Cart and guards an empty direct entry', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(controller.onDelete);

    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    expect(controller.viewState, isA<CheckoutReady>());
    expect(controller.session!.total.minorUnits, 3400);

    final emptyController = CheckoutController(
      cartApi: FakeCheckoutCartApi(
        initialCart: Cart(currency: Currency.usd, items: const <CartItem>[]),
      ),
      checkoutApi: checkoutApi,
    );
    addTearDown(emptyController.onDelete);
    emptyController.onInit();
    await Future<void>.delayed(Duration.zero);
    expect(emptyController.viewState, isA<CheckoutEmptyCart>());
  });

  test(
    'deduplicates pending payment and clears Cart only after success',
    () async {
      final checkoutApi = FakeCheckoutApi();
      final cartApi = FakeCheckoutCartApi();
      addTearDown(checkoutApi.close);
      addTearDown(cartApi.close);
      final pending = Completer<CheckoutPaymentResult>();
      checkoutApi.nextPayment = pending;
      final controller = CheckoutController(
        cartApi: cartApi,
        checkoutApi: checkoutApi,
      );
      addTearDown(controller.onDelete);
      controller.onInit();
      await Future<void>.delayed(Duration.zero);

      final first = controller.pay();
      final duplicate = controller.pay();
      await Future<void>.delayed(Duration.zero);
      expect(controller.session!.paymentState, PaymentState.inProgress);
      expect(checkoutApi.submitCount, 1);
      pending.complete(
        CheckoutPaymentSucceeded(
          demoReceipt(
            attemptId: 'checkout-attempt-1',
            amount: controller.session!.total,
          ),
        ),
      );
      await Future.wait(<Future<void>>[first, duplicate]);

      expect(controller.session!.paymentState, PaymentState.succeeded);
      expect(cartApi.clearCount, 1);
      expect(cartApi.clearedAttemptIds, <String>['checkout-attempt-1']);
    },
  );

  test(
    'failed second card retains Cart and switching to primary retries',
    () async {
      final checkoutApi = FakeCheckoutApi();
      final cartApi = FakeCheckoutCartApi();
      addTearDown(checkoutApi.close);
      addTearDown(cartApi.close);
      final controller = CheckoutController(
        cartApi: cartApi,
        checkoutApi: checkoutApi,
      );
      addTearDown(controller.onDelete);
      controller.onInit();
      await Future<void>.delayed(Duration.zero);

      await controller.selectPaymentMethod('payment-card-secondary');
      await controller.pay();
      expect(controller.session!.paymentState, PaymentState.failed);
      expect(cartApi.clearCount, 0);
      expect(cartApi.current.isEmpty, isFalse);

      await controller.selectPaymentMethod('payment-card-primary');
      await controller.pay();
      expect(controller.session!.paymentState, PaymentState.succeeded);
      expect(cartApi.clearCount, 1);
      expect(checkoutApi.submitCount, 2);
    },
  );

  test(
    'observes external profile changes and releases the subscription',
    () async {
      final checkoutApi = FakeCheckoutApi();
      final cartApi = FakeCheckoutCartApi();
      addTearDown(checkoutApi.close);
      addTearDown(cartApi.close);
      final controller = CheckoutController(
        cartApi: cartApi,
        checkoutApi: checkoutApi,
      );
      controller.onInit();
      await Future<void>.delayed(Duration.zero);
      expect(checkoutApi.activeProfileListeners, 1);

      checkoutApi.emitExternalProfile(
        PaymentProfileSnapshot(
          addresses: checkoutApi.profile.addresses,
          paymentMethods: checkoutApi.profile.paymentMethods,
          selectedAddressId: checkoutApi.profile.selectedAddressId,
          selectedPaymentMethodId: 'payment-card-secondary',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.session!.paymentProfile.selectedPaymentMethodId,
        'payment-card-secondary',
      );

      controller.onDelete();
      await Future<void>.delayed(Duration.zero);
      expect(checkoutApi.activeProfileListeners, 0);
    },
  );

  test('applies the latest external profile after payment finishes', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(controller.onDelete);
    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    final pendingPayment = Completer<CheckoutPaymentResult>();
    checkoutApi.nextPayment = pendingPayment;
    final payment = controller.pay();
    await Future<void>.delayed(Duration.zero);
    checkoutApi.emitExternalProfile(
      PaymentProfileSnapshot(
        addresses: checkoutApi.profile.addresses,
        paymentMethods: checkoutApi.profile.paymentMethods,
        selectedAddressId: checkoutApi.profile.selectedAddressId,
        selectedPaymentMethodId: 'payment-card-primary',
      ),
    );
    checkoutApi.emitExternalProfile(
      PaymentProfileSnapshot(
        addresses: checkoutApi.profile.addresses,
        paymentMethods: checkoutApi.profile.paymentMethods,
        selectedAddressId: checkoutApi.profile.selectedAddressId,
        selectedPaymentMethodId: 'payment-card-secondary',
      ),
    );
    pendingPayment.complete(
      const CheckoutPaymentFailed(
        CheckoutPaymentFailureReason.paymentNotCompleted,
      ),
    );
    await payment;

    expect(controller.session!.paymentState, PaymentState.failed);
    expect(
      controller.session!.paymentProfile.selectedPaymentMethodId,
      'payment-card-secondary',
    );
  });

  test('retries Cart settlement with the same successful attempt', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi()..clearFailuresRemaining = 1;
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(controller.onDelete);
    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    await controller.pay();
    expect(controller.viewState, isA<CheckoutError>());
    expect(checkoutApi.submitCount, 1);
    expect(cartApi.current.isEmpty, isFalse);

    await controller.retry();

    expect(controller.session!.paymentState, PaymentState.succeeded);
    expect(checkoutApi.submitCount, 1);
    expect(cartApi.clearedAttemptIds, <String>[
      'checkout-attempt-1',
      'checkout-attempt-1',
    ]);
    expect(cartApi.current.isEmpty, isTrue);
  });

  test(
    'stores the Receipt with real Cart lines before clearing Cart',
    () async {
      final checkoutApi = FakeCheckoutApi();
      final cartApi = FakeCheckoutCartApi();
      var stored = false;
      addTearDown(checkoutApi.close);
      addTearDown(cartApi.close);
      final controller = CheckoutController(
        cartApi: cartApi,
        checkoutApi: checkoutApi,
        onReceiptReady: (receipt, cart) async {
          expect(receipt.id, isNotEmpty);
          expect(cart.items.first.product.id, 'checkout-product');
          expect(cartApi.current.isEmpty, isFalse);
          stored = true;
        },
      );
      addTearDown(controller.onDelete);
      controller.onInit();
      await Future<void>.delayed(Duration.zero);

      await controller.pay();

      expect(stored, isTrue);
      expect(cartApi.current.isEmpty, isTrue);
    },
  );

  test('retries a failed Receipt sink before clearing Cart', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    var sinkCalls = 0;
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
      onReceiptReady: (receipt, cart) async {
        sinkCalls += 1;
        if (sinkCalls == 1) {
          throw StateError('Orders temporarily unavailable.');
        }
      },
    );
    addTearDown(controller.onDelete);
    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    await controller.pay();
    expect(controller.viewState, isA<CheckoutError>());
    expect(cartApi.current.isEmpty, isFalse);
    expect(cartApi.clearedAttemptIds, isEmpty);

    await controller.retry();
    expect(sinkCalls, 2);
    expect(checkoutApi.submitCount, 1);
    expect(cartApi.current.isEmpty, isTrue);
  });

  test('new Checkout scopes receive process-unique attempt IDs', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);

    final first = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    first.onInit();
    await Future<void>.delayed(Duration.zero);
    await first.pay();
    first.onDelete();

    cartApi.current = checkoutCart();
    final second = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(second.onDelete);
    second.onInit();
    await Future<void>.delayed(Duration.zero);
    await second.pay();

    expect(cartApi.clearedAttemptIds, <String>[
      'checkout-attempt-1',
      'checkout-attempt-2',
    ]);
    expect(checkoutApi.attemptSequence, 2);
    expect(cartApi.current.isEmpty, isTrue);
  });

  test('keeps Checkout ready when a voucher is invalid', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(controller.onDelete);
    controller.onInit();
    await Future<void>.delayed(Duration.zero);

    expect(await controller.applyVoucher('invalid'), isFalse);
    expect(controller.viewState, isA<CheckoutReady>());
    expect(controller.session!.voucher, isNull);
  });

  test('applies a voucher ID requested while Checkout loads', () async {
    final checkoutApi = FakeCheckoutApi();
    final cartApi = FakeCheckoutCartApi();
    addTearDown(checkoutApi.close);
    addTearDown(cartApi.close);
    final controller = CheckoutController(
      cartApi: cartApi,
      checkoutApi: checkoutApi,
    );
    addTearDown(controller.onDelete);

    controller.onInit();
    controller.requestVoucherById('voucher-shoppe-five');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.viewState, isA<CheckoutReady>());
    expect(controller.session!.voucher?.id, 'voucher-shoppe-five');
  });
}
