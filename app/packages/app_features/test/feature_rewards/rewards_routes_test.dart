import 'package:app_data/rewards.dart';
import 'package:app_features/feature_rewards/controllers/rewards_controller.dart';
import 'package:app_features/feature_rewards/pages/vouchers_page.dart';
import 'package:app_features/feature_rewards/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'rewards_test_fixtures.dart';

void main() {
  testWidgets('merges Reward overview, progress, and expiring reminder', (
    tester,
  ) async {
    final fixture = await _pumpRewards(tester);
    addTearDown(fixture.dispose);

    expect(find.text('My Rewards'), findsOneWidget);
    expect(find.byKey(const ValueKey('rewards-balance')), findsOneWidget);
    expect(find.byKey(const ValueKey('rewards-progress')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rewards-voucher-reminder')),
      findsOneWidget,
    );
    expect(find.text('550 points to Platinum'), findsOneWidget);

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('rewards-balance')),
    );
    expect(semantics.label, contains('2450 reward points'));
  });

  testWidgets('dismisses reminder once and restores consumed state', (
    tester,
  ) async {
    final fixture = await _pumpRewards(tester);
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('rewards-dismiss-reminder')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('rewards-voucher-reminder')),
      findsNothing,
    );

    fixture.router.go(vouchersRoutePath);
    await tester.pumpAndSettle();
    fixture.router.go(rewardsRoutePath);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('rewards-voucher-reminder')),
      findsNothing,
    );
  });

  testWidgets('opens vouchers, selects one, uses its stable id, and backs', (
    tester,
  ) async {
    String? selectedVoucherId;
    final fixture = await _pumpRewards(
      tester,
      onUseVoucher: (voucherId) => selectedVoucherId = voucherId,
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('rewards-open-vouchers')));
    await tester.pumpAndSettle();
    expect(fixture.router.state.uri.path, vouchersRoutePath);

    await tester.tap(find.byKey(const ValueKey('voucher-voucher-shoppe-five')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('voucher-use-voucher-shoppe-five')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('voucher-use-voucher-shoppe-five')),
    );
    expect(selectedVoucherId, 'voucher-shoppe-five');

    fixture.router.pop();
    await tester.pumpAndSettle();
    expect(fixture.router.state.uri.path, rewardsRoutePath);
  });

  testWidgets('keeps vouchers reachable on compact scaled viewports', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final fixture = await _pumpRewards(
      tester,
      initialLocation: vouchersRoutePath,
      textScale: 1.3,
    );
    addTearDown(fixture.dispose);

    expect(find.byKey(const ValueKey('vouchers-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('vouchers-scroll')),
      const Offset(0, -420),
    );
    await tester.pump();
    expect(find.text('Redeemed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders empty and retryable error page states', (tester) async {
    final emptyApi = FakeRewardsApi(snapshot: testRewardsSnapshot(empty: true));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: VouchersPage(
          controller: RewardsController(rewardsApi: emptyApi),
          onUseVoucher: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No vouchers yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final errorApi = FakeRewardsApi(
      snapshot: testRewardsSnapshot(),
      failure: const RewardsFailure(RewardsFailureCode.transportUnavailable),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: VouchersPage(
          controller: RewardsController(rewardsApi: errorApi),
          onUseVoucher: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rewards are unavailable'), findsOneWidget);

    errorApi.failure = null;
    await tester.tap(find.byKey(const ValueKey('rewards-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vouchers-scroll')), findsOneWidget);
  });
}

Future<_RewardsRouteFixture> _pumpRewards(
  WidgetTester tester, {
  String initialLocation = rewardsRoutePath,
  double textScale = 1,
  ValueChanged<String>? onUseVoucher,
}) async {
  final stack = TestRewardsStack();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: buildRewardsRoutes(
      rewardsApi: stack.api,
      onUseVoucher: (context, voucherId) => onUseVoucher?.call(voucherId),
    ),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _RewardsRouteFixture(router);
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final class _RewardsRouteFixture {
  const _RewardsRouteFixture(this.router);

  final GoRouter router;

  void dispose() => router.dispose();
}
