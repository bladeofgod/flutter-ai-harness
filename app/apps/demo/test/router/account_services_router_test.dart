import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guards account service deep links while logged out', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    for (final location in <String>[
      rewardsRoutePath,
      vouchersRoutePath,
      supportRoutePath,
      settingsPaymentMethodsRoutePath,
      settingsAddPaymentMethodRoutePath,
      settingsEditPaymentMethodLocation('payment-card-primary'),
      settingsAddressesRoutePath,
      settingsAddAddressRoutePath,
      settingsEditAddressLocation('shipping-home'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(DemoApp(initialLocation: location));
      await tester.pumpAndSettle();

      expect(find.text('Shoppe'), findsOneWidget, reason: location);
      expect(
        find.byKey(const ValueKey('main-bottom-navigation')),
        findsNothing,
      );
    }
  });

  testWidgets('Profile opens Rewards and local Support through public routes', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fixture = await _pumpAuthenticated(tester);
    addTearDown(fixture.authState.dispose);

    await tester.tap(find.byKey(const ValueKey('profile-open-rewards')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rewards-scroll')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rewards-dismiss-reminder')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('expires soon'), findsNothing);
    expect(find.text('1 vouchers available'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-open-support')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-starting')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('support-question-order-status')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-message-input')),
      'Please help with my order.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-send-message')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-open-voucher-voucher-shoppe-five')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('voucher-voucher-shoppe-five')),
      findsOneWidget,
    );
  });

  testWidgets('Rewards applies its shared Voucher ID in Checkout', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fixture = await _pumpAuthenticated(
      tester,
      initialLocation: vouchersRoutePath,
    );
    addTearDown(fixture.authState.dispose);

    await tester.tap(find.byKey(const ValueKey('voucher-voucher-shoppe-five')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('voucher-use-voucher-shoppe-five')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('checkout-scroll')), findsOneWidget);
    expect(find.text(r'$5 off your Demo order'), findsOneWidget);
    expect(find.text(r'Pay $33,00'), findsOneWidget);
  });

  testWidgets('Settings opens shared payment methods and addresses', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fixture = await _pumpAuthenticated(
      tester,
      initialLocation: settingsRoutePath,
    );
    addTearDown(fixture.authState.dispose);

    await tester.tap(find.byKey(const ValueKey('settings-payment-methods')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-payment-scroll')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-addresses')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-address-list')), findsOneWidget);
  });

  testWidgets('invalid Settings payment child link shows a stable fallback', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fixture = await _pumpAuthenticated(
      tester,
      initialLocation: settingsEditPaymentMethodLocation('missing-card'),
    );
    addTearDown(fixture.authState.dispose);

    expect(find.text('Item not found'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });

  testWidgets('Checkout settlement is visible in Payment History', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fixture = await _pumpAuthenticated(
      tester,
      initialLocation: checkoutRoutePath,
    );
    addTearDown(fixture.authState.dispose);

    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('checkout-payment-succeeded')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      DemoApp(
        key: const ValueKey('payment-history-app'),
        featuresRegistry: fixture.registry,
        authStateCoordinator: fixture.authState,
        initialLocation: settingsPaymentMethodsRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('settings-payment-receipt-receipt-checkout-attempt-1'),
      ),
      findsOneWidget,
    );
  });
}

Future<({AuthStateCoordinator authState, FeaturesRegistry registry})>
_pumpAuthenticated(
  WidgetTester tester, {
  String initialLocation = profileRoutePath,
}) async {
  final registry = FeaturesRegistry.local();
  final authState = AuthStateCoordinator();
  authState.authenticate(await _login(registry));
  await tester.pumpWidget(
    DemoApp(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: initialLocation,
    ),
  );
  await tester.pumpAndSettle();
  return (authState: authState, registry: registry);
}

Future<AuthResult> _login(FeaturesRegistry registry) => registry.authApi.login(
  LoginInput(
    email: EmailAddress('romina@example.com'),
    password: Password('shoppe01'),
  ),
);

void _setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.reset);
}
