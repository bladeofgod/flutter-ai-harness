import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guards an unauthenticated Checkout deep link', (tester) async {
    _setPhoneViewport(tester);

    await tester.pumpWidget(const DemoApp(initialLocation: checkoutRoutePath));
    await tester.pumpAndSettle();

    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.byKey(const ValueKey('checkout-scroll')), findsNothing);
  });

  testWidgets('opens Checkout from Cart without the main Shell', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: cartRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cart-checkout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('checkout-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });

  testWidgets('authenticated Checkout deep link stays outside Shell', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: checkoutRoutePath,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('checkout-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });
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
