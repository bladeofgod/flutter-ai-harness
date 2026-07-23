import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guards every logged-out Settings deep link', (tester) async {
    _setPhoneViewport(tester);

    for (final location in <String>[
      settingsRoutePath,
      settingsProfileRoutePath,
      settingsCountryRoutePath,
      settingsAboutRoutePath,
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(DemoApp(initialLocation: location));
      await tester.pump();
      await tester.pump();

      expect(find.text('Shoppe'), findsOneWidget, reason: location);
      expect(find.text('Settings'), findsNothing, reason: location);
    }
  });

  testWidgets('opens Settings from Profile and publishes Profile edits', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));
    final userId = authState.value!.id;
    final sessionId = authState.session!.id;

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: authState),
    );
    await _pumpFeature(tester);
    await tester.tap(find.byKey(const ValueKey('profile-open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-profile-name')),
      'New Shopper',
    );
    await tester.tap(find.byKey(const ValueKey('settings-profile-save')));
    await tester.pumpAndSettle();
    await _pumpFeature(tester);
    expect(authState.value!.displayName, 'New Shopper');
    expect(find.byKey(const ValueKey('settings-scroll')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpFeature(tester);
    expect(find.text('Hello, New Shopper!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-bottom-navigation')),
      findsOneWidget,
    );
    expect(authState.value!.id, userId);
    expect(authState.session!.id, sessionId);
    expect(authState.session!.userId, userId);
  });

  testWidgets('Delete Cancel keeps login and Confirm redirects to Welcome', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: authState),
    );
    await _pumpFeature(tester);
    await tester.tap(find.byKey(const ValueKey('profile-open-settings')));
    await tester.pumpAndSettle();
    final deleteButton = find.byKey(const ValueKey('settings-delete-account'));
    await tester.scrollUntilVisible(
      deleteButton,
      450,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-delete-cancel')));
    await tester.pumpAndSettle();
    expect(authState.isLoggedIn, isTrue);
    expect(find.byKey(const ValueKey('settings-scroll')), findsOneWidget);

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-delete-confirm')));
    await tester.pumpAndSettle();
    expect(authState.isLoggedIn, isFalse);
    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-scroll')), findsNothing);
  });

  testWidgets('opens an authenticated Settings deep link outside the Shell', (
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
        initialLocation: settingsCountryRoutePath,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose Your Country'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });

  testWidgets('Profile My Activity opens the Orders Activity route', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: authState),
    );
    await _pumpFeature(tester);
    await tester.tap(find.byKey(const ValueKey('profile-open-activity')));
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

Future<void> _pumpFeature(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.reset);
}
