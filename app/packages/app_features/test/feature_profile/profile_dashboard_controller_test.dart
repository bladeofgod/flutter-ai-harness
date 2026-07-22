import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_profile/controllers/profile_dashboard_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'profile_test_fixtures.dart';

void main() {
  test('moves from loading to Domain data', () async {
    final completer = Completer<ProfileDashboard>();
    final api = FakeProfileDashboardApi((_) => completer.future);
    final provider = FakeCurrentUserProvider(profileTestUser('Romina'));
    final controller = ProfileDashboardController(
      profileDashboardApi: api,
      currentUserProvider: provider,
    );

    controller.onInit();
    addTearDown(controller.onClose);
    expect(controller.viewState, isA<ProfileDashboardLoading>());

    final dashboard = profileTestDashboard();
    completer.complete(dashboard);
    await _waitForState<ProfileDashboardData>(controller);

    expect(controller.viewState, isA<ProfileDashboardData>());
    expect(
      (controller.viewState as ProfileDashboardData).dashboard,
      same(dashboard),
    );
    expect(api.loadCount, 1);
  });

  test('keeps an empty-section dashboard as successful data', () async {
    final dashboard = profileTestDashboard(emptySections: true);
    final controller = ProfileDashboardController(
      profileDashboardApi: FakeProfileDashboardApi((_) async => dashboard),
      currentUserProvider: FakeCurrentUserProvider(profileTestUser('Romina')),
    );

    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForState<ProfileDashboardData>(controller);

    final state = controller.viewState as ProfileDashboardData;
    expect(state.dashboard.recentlyViewed, isEmpty);
    expect(state.dashboard.stories, isEmpty);
    expect(state.dashboard.recommendations, isEmpty);
  });

  test('exposes a retryable stable failure and then recovers', () async {
    final dashboard = profileTestDashboard();
    final api = FakeProfileDashboardApi((loadCount) async {
      if (loadCount == 1) {
        throw const ProfileDashboardFailure(
          ProfileDashboardFailureCode.unavailable,
        );
      }
      return dashboard;
    });
    final controller = ProfileDashboardController(
      profileDashboardApi: api,
      currentUserProvider: FakeCurrentUserProvider(profileTestUser('Romina')),
    );

    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForState<ProfileDashboardError>(controller);

    final error = controller.viewState as ProfileDashboardError;
    expect(error.failure.code, ProfileDashboardFailureCode.unavailable);

    await controller.retry();

    expect(controller.viewState, isA<ProfileDashboardData>());
    expect(api.loadCount, 2);
  });

  test('tracks current-user changes and releases its listener', () {
    final provider = FakeCurrentUserProvider(profileTestUser('Romina'));
    final controller = ProfileDashboardController(
      profileDashboardApi: FakeProfileDashboardApi(
        (_) async => profileTestDashboard(),
      ),
      currentUserProvider: provider,
    );

    controller.onInit();
    expect(provider.listenerCount, 1);
    expect(controller.currentUser?.displayName, 'Romina');

    provider.setUser(profileTestUser('New Shopper'));
    expect(controller.currentUser?.displayName, 'New Shopper');

    controller.onClose();
    expect(provider.listenerCount, 0);
    provider.setUser(profileTestUser('Ignored User'));
    expect(controller.currentUser?.displayName, 'New Shopper');
  });

  test(
    'reports unexpected lifecycle load errors without mapping them',
    () async {
      final reportedErrors = <FlutterErrorDetails>[];
      final previousHandler = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      addTearDown(() => FlutterError.onError = previousHandler);
      final controller = ProfileDashboardController(
        profileDashboardApi: FakeProfileDashboardApi(
          (_) async => throw StateError('programming failure'),
        ),
        currentUserProvider: FakeCurrentUserProvider(profileTestUser('Romina')),
      );

      controller.onInit();
      addTearDown(controller.onClose);
      await _waitUntil(() => reportedErrors.isNotEmpty);

      expect(reportedErrors, hasLength(1));
      expect(reportedErrors.single.exception, isA<StateError>());
      expect(controller.viewState, isA<ProfileDashboardLoading>());
    },
  );
}

Future<void> _waitForState<T extends ProfileDashboardViewState>(
  ProfileDashboardController controller,
) => _waitUntil(() => controller.viewState is T);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
