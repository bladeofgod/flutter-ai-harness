import 'package:app_data/support.dart';
import 'package:app_features/feature_support/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support_test_fixtures.dart';

void main() {
  testWidgets('merges question, conversation, Voucher and rating states', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    Voucher? openedVoucher;
    final fixture = await _pumpSupport(
      tester,
      onOpenVoucher: (voucher) => openedVoucher = voucher,
    );
    addTearDown(fixture.dispose);

    expect(find.byKey(const ValueKey('support-starting')), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('support-question-order-status')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-status-active')), findsOneWidget);
    expect(find.textContaining('Alex from Shoppe Support'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('support-message-input')),
      'Please help with my order.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-send-message')));
    await tester.pumpAndSettle();
    expect(find.textContaining('fixed local response'), findsOneWidget);
    expect(find.text(r'$5 off your Demo order'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^You(?:\n|$)')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'^Support(?:\n|$)')), findsWidgets);
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey('support-message-support-message-2')),
          )
          .dx,
      greaterThan(
        tester
            .getCenter(
              find.byKey(const ValueKey('support-message-support-message-3')),
            )
            .dx,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('support-open-voucher-voucher-shoppe-five')),
    );
    expect(openedVoucher?.id, 'voucher-shoppe-five');
    expect(openedVoucher?.code, 'SHOPPE5');

    await tester.tap(find.byKey(const ValueKey('support-open-rating')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-rating')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-rating-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-submit-rating')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-rating-complete')),
      findsOneWidget,
    );
    expect(find.textContaining('5-star rating'), findsOneWidget);
  });

  testWidgets('keeps composer reachable with keyboard-sized insets', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568), textScale: 1.3);
    final fixture = await _pumpSupport(
      tester,
      textScale: 1.3,
      keyboardInset: 220,
    );
    addTearDown(fixture.dispose);

    final question = find.byKey(const ValueKey('support-question-return-item'));
    await tester.ensureVisible(question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-message-input')));
    await tester.pump();

    expect(find.byKey(const ValueKey('support-message-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports landscape and scaled starting content', (tester) async {
    const cases = <({Size size, double textScale})>[
      (size: Size(812, 375), textScale: 1),
      (size: Size(375, 812), textScale: 1.3),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size, textScale: testCase.textScale);
      final fixture = await _pumpSupport(tester, textScale: testCase.textScale);
      await tester.pump();
      expect(find.text('How can we help?'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      fixture.dispose();
    }
  });

  testWidgets('Back disposes the draft and re-entry starts a new session', (
    tester,
  ) async {
    final fixture = await _pumpSupport(tester, initialLocation: '/');
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('open-support')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-question-order-status')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-message-input')),
      'Temporary draft',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-home')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-support')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-starting')), findsOneWidget);
    expect(find.text('Temporary draft'), findsNothing);
  });

  testWidgets('shows a repeatable go-to-bottom control for long history', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final fixture = await _pumpSupport(tester);
    addTearDown(fixture.dispose);
    await tester.tap(
      find.byKey(const ValueKey('support-question-payment-question')),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 7; index += 1) {
      await tester.enterText(
        find.byKey(const ValueKey('support-message-input')),
        'Message number $index with enough text for scrolling.',
      );
      await tester.tap(find.byKey(const ValueKey('support-send-message')));
      await tester.pumpAndSettle();
    }
    await tester.drag(
      find.byKey(const ValueKey('support-message-list')),
      const Offset(0, 320),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('support-scroll-bottom')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-scroll-bottom')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<_SupportRouteFixture> _pumpSupport(
  WidgetTester tester, {
  ValueChanged<Voucher>? onOpenVoucher,
  double textScale = 1,
  double keyboardInset = 0,
  String initialLocation = supportRoutePath,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            key: const ValueKey('support-home'),
            child: FilledButton(
              key: const ValueKey('open-support'),
              onPressed: () => context.push(supportRoutePath),
              child: const Text('Open Support'),
            ),
          ),
        ),
      ),
      ...buildSupportRoutes(
        supportChatApi: createSupportApi(),
        transitionDelay: immediateSupportDelay,
        onOpenVoucher: (context, voucher) => onOpenVoucher?.call(voucher),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _SupportRouteFixture(router);
}

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

final class _SupportRouteFixture {
  const _SupportRouteFixture(this.router);

  final GoRouter router;

  void dispose() => router.dispose();
}
