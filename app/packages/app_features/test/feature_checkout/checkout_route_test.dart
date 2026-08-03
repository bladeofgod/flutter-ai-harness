import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_checkout/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'checkout_test_fixtures.dart';

void main() {
  testWidgets('applies a shared voucher ID from the Checkout location', (
    tester,
  ) async {
    final fixture = await _pumpCheckout(
      tester,
      initialLocation: checkoutLocationWithVoucher('voucher-shoppe-five'),
    );
    addTearDown(fixture.close);
    await tester.pumpAndSettle();

    expect(find.text(r'Pay $29,00'), findsOneWidget);
    expect(find.text(r'$5 off your Demo order'), findsOneWidget);
  });

  testWidgets('renders Payment and applies node 49/50 voucher states', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final fixture = await _pumpCheckout(tester);
    addTearDown(fixture.close);

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text(r'Pay $34,00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('checkout-address-summary')),
      findsOneWidget,
    );

    await tester.tap(find.text('Add voucher'));
    expect(
      fixture.router.routeInformationProvider.value.uri.path,
      checkoutVoucherRoutePath,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkout-voucher-code')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('checkout-voucher-code')),
      'invalid',
    );
    await tester.tap(find.byKey(const ValueKey('checkout-apply-voucher')));
    await tester.pump();
    await tester.pump();
    expect(find.text('This Demo voucher is not available'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('checkout-voucher-code')),
      'SHOPPE5',
    );
    await tester.tap(find.byKey(const ValueKey('checkout-apply-voucher')));
    await tester.pumpAndSettle();

    expect(
      fixture.router.routeInformationProvider.value.uri.path,
      checkoutRoutePath,
    );
    expect(find.text(r'Pay $29,00'), findsOneWidget);
    expect(find.text(r'$5 off your Demo order'), findsOneWidget);
    expect(find.text(r'SHOPPE5  -$5,00'), findsOneWidget);
  });

  testWidgets('validates and saves an address with keyboard insets', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final fixture = await _pumpCheckout(tester, keyboardInset: 220);
    addTearDown(fixture.close);

    await tester.tap(find.text('Shipping Address'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkout-address-form')), findsOneWidget);
    expect(
      MediaQuery.viewInsetsOf(
        tester.element(find.byType(Scaffold).last),
      ).bottom,
      220,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('checkout-save-address')))
          .bottom,
      lessThanOrEqualTo(568),
    );

    final name = find.descendant(
      of: find.byKey(const ValueKey('checkout-address-name')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(name, '');
    await tester.tap(find.byKey(const ValueKey('checkout-save-address')));
    await tester.pump();
    expect(find.text('This field is required'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(name, 'A Customer With A Long Display Name');
    final street = find.descendant(
      of: find.byKey(const ValueKey('checkout-address-street')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(
      street,
      '100 A deliberately long street address used by the local Demo',
    );
    await tester.tap(find.byKey(const ValueKey('checkout-save-address')));
    await tester.pumpAndSettle();

    expect(
      fixture.router.routeInformationProvider.value.uri.path,
      checkoutRoutePath,
    );
    expect(find.text('A Customer With A Long Display Name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'merges progress, failure, retry, and success into one result route',
    (tester) async {
      await _setViewport(tester, const Size(375, 812));
      final fixture = await _pumpCheckout(tester);
      addTearDown(fixture.close);

      await tester.tap(
        find.byKey(const ValueKey('checkout-payment-method-summary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('checkout-payment-method-payment-card-secondary'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('checkout-payment-method-payment-card-secondary'),
        ),
      );
      await tester.pumpAndSettle();

      final failedAttempt = Completer<CheckoutPaymentResult>();
      fixture.checkoutApi.nextPayment = failedAttempt;
      await tester.tap(find.byKey(const ValueKey('checkout-pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('checkout-payment-progress')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('checkout-payment-progress')),
        findsOneWidget,
      );
      failedAttempt.complete(
        const CheckoutPaymentFailed(
          CheckoutPaymentFailureReason.paymentNotCompleted,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('checkout-payment-failed')),
        findsOneWidget,
      );
      expect(fixture.cartApi.current.isEmpty, isFalse);
      expect(fixture.cartApi.clearCount, 0);

      await tester.tap(
        find.byKey(const ValueKey('checkout-change-payment-method')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('checkout-payment-method-payment-card-primary'),
        ),
      );
      await tester.pumpAndSettle();

      final successfulAttempt = Completer<CheckoutPaymentResult>();
      fixture.checkoutApi.nextPayment = successfulAttempt;
      await tester.tap(find.byKey(const ValueKey('checkout-result-pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.byKey(const ValueKey('checkout-payment-progress')),
        findsOneWidget,
      );
      successfulAttempt.complete(
        CheckoutPaymentSucceeded(
          demoReceipt(
            attemptId: 'checkout-attempt-2',
            amount: Money(currency: Currency.usd, minorUnits: 3400),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('checkout-payment-succeeded')),
        findsOneWidget,
      );
      expect(find.text('Demo payment completed'), findsOneWidget);
      expect(find.textContaining('No real card was charged'), findsOneWidget);
      expect(find.textContaining('Your Card Been Charged'), findsNothing);
      expect(fixture.cartApi.clearCount, 1);
      expect(fixture.cartApi.current.isEmpty, isTrue);
    },
  );

  testWidgets('redirects an empty Cart and releases the shared route scope', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final empty = FakeCheckoutCartApi(
      initialCart: Cart(currency: Currency.usd, items: const <CartItem>[]),
    );
    final emptyFixture = await _pumpCheckout(
      tester,
      cartApi: empty,
      initialLocation: checkoutAddressRoutePath,
    );
    await tester.pump();
    expect(
      emptyFixture.router.routeInformationProvider.value.uri.path,
      '/cart',
    );
    expect(emptyFixture.navigation.emptyRedirectCount, 1);

    await tester.pumpWidget(const SizedBox());
    await emptyFixture.close();
    final fixture = await _pumpCheckout(tester);
    addTearDown(fixture.close);
    expect(fixture.checkoutApi.activeProfileListeners, 1);

    await tester.tap(find.text('Add voucher'));
    await tester.pumpAndSettle();
    expect(fixture.checkoutApi.activeProfileListeners, 1);
    fixture.router.go('/outside');
    await tester.pumpAndSettle();
    expect(fixture.checkoutApi.activeProfileListeners, 0);
  });

  testWidgets('direct child links share one Controller and cancel drafts', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final fixture = await _pumpCheckout(
      tester,
      initialLocation: checkoutVoucherRoutePath,
    );
    addTearDown(fixture.close);

    expect(find.byKey(const ValueKey('checkout-voucher-code')), findsOneWidget);
    expect(fixture.checkoutApi.activeProfileListeners, 1);
    await tester.enterText(
      find.byKey(const ValueKey('checkout-voucher-code')),
      'UNSAVED',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Add voucher'), findsOneWidget);

    await tester.tap(find.text('Add voucher'));
    await tester.pumpAndSettle();
    expect(find.text('UNSAVED'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('checkout-voucher-code')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('shows a retryable load error without changing the Cart', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final checkoutApi = FakeCheckoutApi()
      ..loadError = const CheckoutFailure(
        CheckoutFailureCode.transportUnavailable,
      );
    final fixture = await _pumpCheckout(tester, checkoutApi: checkoutApi);
    addTearDown(fixture.close);

    expect(find.text('Checkout is unavailable'), findsOneWidget);
    expect(fixture.cartApi.current.isEmpty, isFalse);
    checkoutApi.loadError = null;
    await tester.tap(find.byKey(const ValueKey('checkout-retry-load')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text(r'Pay $34,00'), findsOneWidget);
  });

  testWidgets(
    'keeps fixed actions and long content reachable across viewports',
    (tester) async {
      const cases = <({Size size, double textScale})>[
        (size: Size(320, 568), textScale: 1),
        (size: Size(812, 375), textScale: 1),
        (size: Size(375, 812), textScale: 1.3),
      ];
      for (final testCase in cases) {
        await tester.pumpWidget(const SizedBox());
        await _setViewport(tester, testCase.size);
        final fixture = await _pumpCheckout(
          tester,
          textScale: testCase.textScale,
        );
        final checkoutScroll = find.byKey(const ValueKey('checkout-scroll'));
        await tester.scrollUntilVisible(
          find.text('Total'),
          180,
          scrollable: find
              .descendant(of: checkoutScroll, matching: find.byType(Scrollable))
              .first,
        );
        await tester.drag(checkoutScroll, const Offset(0, -140));
        await tester.pump();
        expect(find.byKey(const ValueKey('checkout-pay')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('checkout-pay')).hitTestable(),
          findsOneWidget,
        );
        final totalRect = tester.getRect(find.text('Total'));
        final scrollRect = tester.getRect(checkoutScroll);
        expect(totalRect.top, greaterThanOrEqualTo(scrollRect.top));
        expect(totalRect.bottom, lessThanOrEqualTo(scrollRect.bottom));
        final payRect = tester.getRect(
          find.byKey(const ValueKey('checkout-pay')),
        );
        expect(payRect.top, greaterThanOrEqualTo(0));
        expect(payRect.bottom, lessThanOrEqualTo(testCase.size.height));
        expect(checkoutScroll, findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${testCase.size}');
        await tester.pumpWidget(const SizedBox());
        await fixture.close();
      }
    },
  );

  testWidgets('exposes selected card, total, actions, and progress semantics', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final semantics = tester.ensureSemantics();
    final fixture = await _pumpCheckout(tester);
    addTearDown(fixture.close);

    final checkoutScroll = find.byKey(const ValueKey('checkout-scroll'));
    await tester.scrollUntilVisible(
      find.text('Total'),
      180,
      scrollable: find
          .descendant(of: checkoutScroll, matching: find.byType(Scrollable))
          .first,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Order total \$34,00')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(r'Pay $34,00'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('checkout-payment-method-summary')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey(
                'checkout-payment-method-semantics-payment-card-primary',
              ),
            ),
          )
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final pending = Completer<CheckoutPaymentResult>();
    fixture.checkoutApi.nextPayment = pending;
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('checkout-payment-progress-semantics')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    pending.complete(
      CheckoutPaymentSucceeded(
        demoReceipt(
          attemptId: 'checkout-attempt-1',
          amount: Money(currency: Currency.usd, minorUnits: 3400),
        ),
      ),
    );
    await tester.pump();
    semantics.dispose();
  });
}

final class _CheckoutFixture {
  const _CheckoutFixture({
    required this.router,
    required this.checkoutApi,
    required this.cartApi,
    required this.navigation,
  });

  final GoRouter router;
  final FakeCheckoutApi checkoutApi;
  final FakeCheckoutCartApi cartApi;
  final _NavigationStats navigation;

  Future<void> close() async {
    router.dispose();
    await checkoutApi.close();
    await cartApi.close();
  }
}

Future<_CheckoutFixture> _pumpCheckout(
  WidgetTester tester, {
  FakeCheckoutCartApi? cartApi,
  FakeCheckoutApi? checkoutApi,
  String initialLocation = checkoutRoutePath,
  double keyboardInset = 0,
  double textScale = 1,
}) async {
  final resolvedCheckoutApi = checkoutApi ?? FakeCheckoutApi();
  final resolvedCartApi = cartApi ?? FakeCheckoutCartApi();
  final navigation = _NavigationStats();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      ...buildCheckoutRoutes(
        cartApi: resolvedCartApi,
        checkoutApi: resolvedCheckoutApi,
        onEmptyCart: (context) {
          navigation.emptyRedirectCount += 1;
          context.go('/cart');
        },
        onCompleted: (context) => context.go('/shop'),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const Text('Cart')),
      GoRoute(path: '/shop', builder: (context, state) => const Text('Shop')),
      GoRoute(
        path: '/outside',
        builder: (context, state) => const Text('Outside'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _CheckoutFixture(
    router: router,
    checkoutApi: resolvedCheckoutApi,
    cartApi: resolvedCartApi,
    navigation: navigation,
  );
}

final class _NavigationStats {
  int emptyRedirectCount = 0;
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
