import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'guards Search, Promotions and Orders deep links when logged out',
    (tester) async {
      _setPhoneViewport(tester);
      for (final location in <String>[
        searchRoutePath,
        flashSaleRoutePath,
        liveRoutePath,
        storyLocation('story-style-edit'),
        activityRoutePath,
        orderDetailRoutePath('order-1001'),
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
    },
  );

  testWidgets('Shop opens Search and Promotions through public routes', (
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
    await tester.tap(find.byKey(const ValueKey('shop-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-input')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-flash-sale')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flash-sale-scroll')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-live')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('live-demo-preview-state')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-story')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-progress')), findsOneWidget);
  });

  testWidgets('opens authenticated Orders Activity outside the Shell', (
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
        initialLocation: activityRoutePath,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('orders-activity-scroll')),
      findsOneWidget,
    );
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
