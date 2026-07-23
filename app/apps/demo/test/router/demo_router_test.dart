import 'dart:convert';
import 'dart:typed_data';

import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:demo_app/demo_app.dart';
import 'package:demo_app/router/demo_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('redirects a logged-out profile deep link to Welcome', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    await tester.pumpWidget(const DemoApp(initialLocation: profileRoutePath));
    await tester.pump();

    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.text('Hello, Romina!'), findsNothing);
  });

  testWidgets('redirects a logged-out Shop deep link to Welcome', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    await tester.pumpWidget(const DemoApp(initialLocation: shopRoutePath));
    await tester.pump();

    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.text('Big Sale'), findsNothing);
  });

  testWidgets('keeps an authenticated Shop deep link at the real page', (
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
    await _pumpProfile(tester);

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Big Sale'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('navigates all five authenticated branches through the Shell', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: profileRoutePath,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpProfile(tester);
    expect(
      find.byKey(const ValueKey('main-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Profile'), findsOneWidget);

    for (final destination in <({String label, String path, String content})>[
      (label: 'Shop', path: shopRoutePath, content: 'Big Sale'),
      (label: 'Categories', path: categoriesRoutePath, content: 'All Items'),
      (label: 'Wishlist', path: wishlistRoutePath, content: 'Wishlist'),
      (label: 'Cart', path: cartRoutePath, content: 'Cart'),
      (label: 'Profile', path: profileRoutePath, content: 'Hello, Romina!'),
    ]) {
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'main-navigation-${destination.label.toLowerCase()}',
          ),
        ),
      );
      await _pumpProfile(tester);
      expect(router.routeInformationProvider.value.uri.path, destination.path);
      expect(find.text(destination.content), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            'main-navigation-${destination.label.toLowerCase()}',
          ),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preserves branch child stacks and repeats return to branch root',
    (tester) async {
      _setPhoneViewport(tester);
      final registry = FeaturesRegistry.local();
      final authState = AuthStateCoordinator();
      addTearDown(authState.dispose);
      authState.authenticate(await _login(registry));
      final router = createDemoRouter(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: profileRoutePath,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('main-navigation-wishlist')));
      await _pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('open-recently-viewed')));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('recently-viewed-scroll')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('main-navigation-shop')));
      await _pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('main-navigation-wishlist')));
      await _pumpProfile(tester);
      expect(
        find.byKey(const ValueKey('recently-viewed-scroll')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('main-navigation-wishlist')));
      await _pumpProfile(tester);
      expect(find.text('Wishlist'), findsOneWidget);
      expect(find.byKey(const ValueKey('wishlist-scroll')), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, wishlistRoutePath);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guards every main branch deep link while logged out', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    const mainLinks = <String>[
      shopRoutePath,
      wishlistRoutePath,
      categoriesRoutePath,
      cartRoutePath,
      profileRoutePath,
      recentlyViewedRoutePath,
    ];

    for (final link in mainLinks) {
      final registry = FeaturesRegistry.local();
      final authState = AuthStateCoordinator();
      final router = createDemoRouter(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: link,
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      expect(find.text('Shoppe'), findsOneWidget, reason: link);
      expect(
        find.byKey(const ValueKey('main-bottom-navigation')),
        findsNothing,
      );
      expect(find.text('Login'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      router.dispose();
      authState.dispose();
    }
  });

  testWidgets(
    'Back leaves a child branch without returning to Auth and keeps scroll',
    (tester) async {
      _setPhoneViewport(tester);
      final registry = FeaturesRegistry.local();
      final authState = AuthStateCoordinator();
      addTearDown(authState.dispose);
      authState.authenticate(await _login(registry));
      final router = createDemoRouter(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: profileRoutePath,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('main-navigation-shop')));
      await _pumpProfile(tester);

      final shopScroll = find.byKey(const ValueKey('shop-dashboard-scroll'));
      final shopScrollable = find
          .descendant(of: shopScroll, matching: find.byType(Scrollable))
          .first;
      final shopState = tester.state<ScrollableState>(shopScrollable);
      await tester.drag(shopScroll, const Offset(0, -500));
      await tester.pump();
      final retainedOffset = shopState.position.pixels;
      expect(retainedOffset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('main-navigation-wishlist')));
      await _pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('open-recently-viewed')));
      await _pumpProfile(tester);
      expect(
        find.byKey(const ValueKey('recently-viewed-scroll')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Wishlist'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(find.text('Shoppe'), findsNothing);
      final wishlistRootPath = router.routeInformationProvider.value.uri.path;
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Login'), findsNothing);
      expect(find.text('Shoppe'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, wishlistRootPath);

      await tester.tap(find.byKey(const ValueKey('main-navigation-shop')));
      await _pumpProfile(tester);
      final restoredShopScrollable = find
          .descendant(
            of: find.byKey(const ValueKey('shop-dashboard-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(restoredShopScrollable).position.pixels,
        greaterThanOrEqualTo(retainedOffset),
      );
      final restoredShopState = tester.state<ScrollableState>(
        restoredShopScrollable,
      );
      restoredShopState.position.jumpTo(
        restoredShopState.position.maxScrollExtent,
      );
      await tester.pump();

      final bar = tester.getRect(
        find.byKey(const ValueKey('main-bottom-navigation')),
      );
      expect(
        restoredShopState.position.pixels,
        restoredShopState.position.maxScrollExtent,
      );
      expect(bar.top, greaterThan(0));
      final lastRecommendation = find.byKey(
        const ValueKey('shop-recommendation-product-5'),
      );
      expect(lastRecommendation, findsOneWidget);
      expect(
        tester.getRect(lastRecommendation).bottom,
        lessThanOrEqualTo(bar.top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens every main branch from an authenticated deep link', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    const links = <({String path, String label, String content})>[
      (path: shopRoutePath, label: 'Shop', content: 'Big Sale'),
      (path: wishlistRoutePath, label: 'Wishlist', content: 'Wishlist'),
      (path: categoriesRoutePath, label: 'Categories', content: 'All Items'),
      (path: cartRoutePath, label: 'Cart', content: 'Cart'),
      (path: profileRoutePath, label: 'Profile', content: 'Hello, Romina!'),
      (
        path: recentlyViewedRoutePath,
        label: 'Wishlist',
        content: 'Recently viewed',
      ),
    ];

    for (final link in links) {
      final registry = FeaturesRegistry.local();
      final authState = AuthStateCoordinator();
      authState.authenticate(await _login(registry));
      final router = createDemoRouter(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: link.path,
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpProfile(tester);

      expect(find.text(link.content), findsOneWidget, reason: link.path);
      expect(
        find.byKey(
          ValueKey<String>('main-navigation-${link.label.toLowerCase()}'),
        ),
        findsOneWidget,
        reason: link.path,
      );
      expect(
        tester
            .getSemantics(
              find.byKey(
                ValueKey<String>(
                  'main-navigation-semantics-${link.label.toLowerCase()}',
                ),
              ),
            )
            .flagsCollection
            .isSelected,
        isTrue,
        reason: link.path,
      );
      expect(router.routeInformationProvider.value.uri.path, link.path);

      await tester.pumpWidget(const SizedBox());
      router.dispose();
      authState.dispose();
    }
    semantics.dispose();
  });

  testWidgets('logout from a child branch returns to Welcome', (tester) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    authState.authenticate(await _login(registry));
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: recentlyViewedRoutePath,
    );
    addTearDown(router.dispose);
    addTearDown(authState.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpProfile(tester);
    expect(
      find.byKey(const ValueKey('recently-viewed-scroll')),
      findsOneWidget,
    );

    authState.logout();
    await _pumpRouterRefresh(tester);
    expect(find.text('Shoppe'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, welcomeRoutePath);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redirects an authenticated Welcome location to Profile', (
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
    await _pumpProfile(tester);

    expect(find.text('Hello, Romina!'), findsOneWidget);
    expect(find.text('Recently viewed'), findsOneWidget);
  });

  testWidgets('redirects an authenticated Auth deep link to Profile', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: '/auth/register',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpProfile(tester);

    expect(router.routeInformationProvider.value.uri.path, profileRoutePath);
    expect(find.text('Hello, Romina!'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens registration and cancels back to Welcome', (tester) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
    );
    addTearDown(authState.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.tap(find.text("Let's get started"));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      registrationRoutePath,
    );
    expect(find.text('Create\nAccount'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, welcomeRoutePath);
    expect(find.text('Shoppe'), findsOneWidget);
  });

  testWidgets('registration authenticates once and redirects to Profile', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: registrationRoutePath,
    );
    addTearDown(authState.dispose);
    addTearDown(router.dispose);
    var notificationCount = 0;
    authState.addListener(() => notificationCount += 1);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.enterText(
      _registrationField('registration-email'),
      'new.shopper@example.com',
    );
    await tester.enterText(
      _registrationField('registration-password'),
      'shopper1',
    );
    await tester.enterText(
      _registrationField('registration-phone'),
      '7700900123',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(authState.isLoggedIn, isTrue);
    expect(authState.value?.displayName, 'New Shopper');
    expect(notificationCount, 1);
    expect(router.routeInformationProvider.value.uri.path, profileRoutePath);
    expect(find.text('Hello, New Shopper!'), findsOneWidget);
    expect(find.text('Create\nAccount'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile uses the avatar returned by registration', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    final avatarBytes = _onePixelPng();
    final result = await registry.authApi.register(
      RegistrationInput(
        email: EmailAddress('custom.avatar@example.com'),
        password: Password('avatar01'),
        callingCode: CountryCallingCode('+86'),
        phoneNumber: PhoneNumber('13800138000'),
        avatar: UserAvatar.memory(avatarBytes),
      ),
    );
    authState.authenticate(result);

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: authState),
    );
    await _pumpProfile(tester);

    expect(authState.value?.avatar.kind, UserAvatarKind.memory);
    expect(authState.value?.avatar.bytes, orderedEquals(avatarBytes));
    final avatarImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('profile-avatar')),
        matching: find.byType(Image),
      ),
    );
    expect(avatarImage.image, isA<MemoryImage>());
    expect(
      (avatarImage.image as MemoryImage).bytes,
      orderedEquals(avatarBytes),
    );
  });

  testWidgets('direct Password and Recovery links redirect to Login', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    for (final path in <String>[passwordRoutePath, recoveryRoutePath]) {
      final registry = FeaturesRegistry.local();
      final authState = AuthStateCoordinator();
      final router = createDemoRouter(
        featuresRegistry: registry,
        authStateCoordinator: authState,
        initialLocation: path,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
      expect(find.text('Login'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      router.dispose();
      authState.dispose();
    }
  });

  testWidgets('an unregistered email authenticates once and opens Profile', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: loginRoutePath,
    );
    addTearDown(authState.dispose);
    addTearDown(router.dispose);
    var notificationCount = 0;
    authState.addListener(() => notificationCount += 1);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.enterText(
      _loginField('login-email'),
      'first.visit@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, passwordRoutePath);
    expect(find.text('Hello, First Visit!!'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      'welcome1',
    );
    await tester.pumpAndSettle();

    expect(authState.isLoggedIn, isTrue);
    expect(authState.value?.displayName, 'First Visit');
    expect(notificationCount, 1);
    expect(router.routeInformationProvider.value.uri.path, profileRoutePath);
    expect(find.text('Hello, First Visit!'), findsOneWidget);
    expect(find.text('Type your password'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reserved password reaches the recovery entry', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    final router = createDemoRouter(
      featuresRegistry: registry,
      authStateCoordinator: authState,
      initialLocation: loginRoutePath,
    );
    addTearDown(authState.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.enterText(
      _loginField('login-email'),
      'error.demo@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      '00000000',
    );
    await tester.pumpAndSettle();

    expect(authState.isLoggedIn, isFalse);
    expect(router.routeInformationProvider.value.uri.path, passwordRoutePath);
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout redirects Profile back to Welcome', (tester) async {
    _setPhoneViewport(tester);
    final registry = FeaturesRegistry.local();
    final authState = AuthStateCoordinator();
    addTearDown(authState.dispose);
    authState.authenticate(await _login(registry));

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: authState),
    );
    await _pumpProfile(tester);
    authState.logout();
    await _pumpRouterRefresh(tester);

    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.text('Hello, Romina!'), findsNothing);
  });

  testWidgets('renders the shell error page for an unknown route', (
    tester,
  ) async {
    _setPhoneViewport(tester);

    await tester.pumpWidget(const DemoApp(initialLocation: '/missing-page'));
    await tester.pump();

    expect(find.text('Page not found'), findsOneWidget);
  });
}

Finder _registrationField(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

Finder _loginField(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

Future<AuthResult> _login(FeaturesRegistry registry) {
  return registry.authApi.login(
    LoginInput(
      email: EmailAddress('romina@example.com'),
      password: Password('shoppe01'),
    ),
  );
}

Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpRouterRefresh(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.reset);
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);
