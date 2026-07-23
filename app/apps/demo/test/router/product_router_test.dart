import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens Product detail from an authenticated deep link', (
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
        initialLocation: productDetailLocation('product-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-detail-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });

  testWidgets('Wishlist product action opens the shared Product route', (
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
        initialLocation: wishlistRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wishlist-open-product-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-detail-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
    expect(find.byKey(const ValueKey('product-title')), findsOneWidget);
  });

  testWidgets('Wishlist Add to Cart mutates the shared Cart', (tester) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: wishlistRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wishlist-add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('main-navigation-cart')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cart-item-product-1::color=pink&size=m')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Shop and Cart product cards use the same Product route', (
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
        initialLocation: shopRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shop-open-product-product-21')),
      520,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('shop-dashboard-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.byKey(const ValueKey('shop-open-product-product-21')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-detail-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('main-bottom-navigation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('main-navigation-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cart-open-product-product-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-detail-scroll')), findsOneWidget);
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
