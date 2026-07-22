import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:app_features/feature_profile/controllers/profile_dashboard_controller.dart';
import 'package:app_features/feature_profile/pages/profile_dashboard_page.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'profile_test_fixtures.dart';

void main() {
  testWidgets('matches the Profile first-viewport structure', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester);

    expect(find.text('Hello, Romina!'), findsOneWidget);
    expect(find.text('Announcement'), findsOneWidget);
    expect(find.text('Recently viewed'), findsOneWidget);
    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Stories'), findsOneWidget);
    expect(find.text('To Pay'), findsOneWidget);
    expect(find.text('To Receive'), findsOneWidget);
    expect(find.text('To Review'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey('profile-avatar')),
    );
    final bottomRect = tester.getRect(
      find.byKey(const ValueKey('profile-bottom-navigation')),
    );
    expect(avatarRect.size, const Size(44, 44));
    expect(bottomRect.height, 50);
    expect(find.bySemanticsLabel('Profile'), findsOneWidget);
  });

  testWidgets('keeps section order and the bottom navigation fixed', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester);
    final scrollView = find.byKey(const ValueKey('profile-dashboard-scroll'));
    final verticalScrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;
    final initialBottomRect = tester.getRect(
      find.byKey(const ValueKey('profile-bottom-navigation')),
    );
    const sectionTitles = <String>[
      'Stories',
      'New Items',
      'Most Popular',
      'Categories',
      'Flash Sale',
      'Top Products',
      'Just for You',
    ];
    var previousOffset = 0.0;

    for (final title in sectionTitles) {
      await tester.scrollUntilVisible(
        find.text(title),
        450,
        scrollable: verticalScrollable,
      );
      final scrollableState = tester.state<ScrollableState>(verticalScrollable);
      expect(
        scrollableState.position.pixels,
        greaterThanOrEqualTo(previousOffset),
      );
      previousOffset = scrollableState.position.pixels;
    }

    final finalBottomRect = tester.getRect(
      find.byKey(const ValueKey('profile-bottom-navigation')),
    );
    expect(finalBottomRect, initialBottomRect);
    expect(previousOffset, greaterThan(0));
  });

  testWidgets('provides bounded horizontal scrolling for all designed rails', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester);
    final verticalScroll = find.byKey(
      const ValueKey('profile-dashboard-scroll'),
    );
    final verticalScrollable = find
        .descendant(of: verticalScroll, matching: find.byType(Scrollable))
        .first;
    const rails = <({String title, String key})>[
      (title: 'Stories', key: 'profile-stories-list'),
      (title: 'New Items', key: 'profile-new-items-list'),
      (title: 'Most Popular', key: 'profile-most-popular-list'),
      (title: 'Top Products', key: 'profile-top-products-list'),
    ];

    for (final rail in rails) {
      await tester.scrollUntilVisible(
        find.text(rail.title),
        450,
        scrollable: verticalScrollable,
      );
      final list = find.byKey(ValueKey<String>(rail.key));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: rail.title,
      );
      await tester.drag(list, const Offset(-120, 0));
      await tester.pump();
      expect(state.position.pixels, greaterThan(0), reason: rail.title);
    }
  });

  testWidgets('renders retryable error and recovers', (tester) async {
    final dashboard = profileTestDashboard();
    final api = FakeProfileDashboardApi((loadCount) async {
      if (loadCount == 1) {
        throw const ProfileDashboardFailure(
          ProfileDashboardFailureCode.unavailable,
        );
      }
      return dashboard;
    });
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester, api: api);

    expect(find.text('Unable to load your profile'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hello, Romina!'), findsOneWidget);
    expect(api.loadCount, 2);
  });

  testWidgets('keeps a stable loading layout until data arrives', (
    tester,
  ) async {
    final completer = Completer<ProfileDashboard>();
    final api = FakeProfileDashboardApi((_) => completer.future);
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester, api: api);

    expect(find.byKey(const ValueKey('profile-loading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-bottom-navigation')),
      findsOneWidget,
    );

    completer.complete(profileTestDashboard());
    await tester.pump();
    await tester.pump();

    expect(find.text('Hello, Romina!'), findsOneWidget);
  });

  testWidgets('shows stable empty-section states', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(
      tester,
      dashboard: profileTestDashboard(emptySections: true),
    );

    expect(find.text('No recently viewed items yet.'), findsOneWidget);
    expect(find.text('No stories available.'), findsOneWidget);
    expect(find.text('No new items available.'), findsOneWidget);
    final scrollView = find.byKey(const ValueKey('profile-dashboard-scroll'));
    await tester.scrollUntilVisible(
      find.text('Just for You'),
      500,
      scrollable: find
          .descendant(of: scrollView, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('No recommendations available.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reacts to user changes and releases the Provider listener', (
    tester,
  ) async {
    final provider = FakeCurrentUserProvider(profileTestUser('Romina'));
    await _setViewport(tester, const Size(375, 812));
    await _pumpProfile(tester, provider: provider);
    expect(provider.listenerCount, 1);

    provider.setUser(profileTestUser('New Shopper'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hello, New Shopper!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(provider.listenerCount, 0);
  });

  testWidgets('has no overflow on compact, landscape, or scaled viewports', (
    tester,
  ) async {
    const cases = <({Size size, double textScale})>[
      (size: Size(320, 568), textScale: 1),
      (size: Size(812, 375), textScale: 1),
      (size: Size(375, 812), textScale: 1.3),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpProfile(tester, textScale: testCase.textScale);
      final scrollView = find.byKey(const ValueKey('profile-dashboard-scroll'));
      await tester.scrollUntilVisible(
        find.text('Just for You'),
        500,
        scrollable: find
            .descendant(of: scrollView, matching: find.byType(Scrollable))
            .first,
      );

      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      expect(
        find.byKey(const ValueKey('profile-bottom-navigation')),
        findsOneWidget,
      );
    }
  });

  testWidgets('buildProfileRoutes creates the real Profile destination', (
    tester,
  ) async {
    final provider = FakeCurrentUserProvider(profileTestUser('Romina'));
    final api = FakeProfileDashboardApi((_) async => profileTestDashboard());
    final router = GoRouter(
      initialLocation: profileRoutePath,
      routes: buildProfileRoutes(
        profileDashboardApi: api,
        currentUserProvider: provider,
      ),
    );
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, profileRoutePath);
    expect(find.text('Hello, Romina!'), findsOneWidget);
    expect(provider.listenerCount, 1);

    await tester.pumpWidget(const SizedBox());
    expect(provider.listenerCount, 0);
  });
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  ProfileDashboard? dashboard,
  FakeProfileDashboardApi? api,
  FakeCurrentUserProvider? provider,
  double textScale = 1,
}) async {
  final resolvedApi =
      api ??
      FakeProfileDashboardApi((_) async => dashboard ?? profileTestDashboard());
  final resolvedProvider =
      provider ?? FakeCurrentUserProvider(profileTestUser('Romina'));
  final controller = ProfileDashboardController(
    profileDashboardApi: resolvedApi,
    currentUserProvider: resolvedProvider,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProfileDashboardPage(controller: controller),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
