import 'dart:ui' show SemanticsAction;

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/feature_settings/api/local_settings_payment_api.dart';
import 'package:app_features/feature_settings/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('adds a masked card and shows the result overlay', (
    tester,
  ) async {
    final fixture = _RouteFixture();
    addTearDown(fixture.close);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-payment-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-card-holder')),
      'Olivia Martin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-card-number')),
      '4242424242424242',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-card-expiry')),
      '12/30',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-card-security-code')),
      '123',
    );
    await tester.tap(find.byKey(const ValueKey('settings-card-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-card-saved-dialog')),
      findsOneWidget,
    );
    expect(find.text('4242424242424242'), findsNothing);
    expect(find.text('123'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-card-saved-done')));
    await _pumpNavigation(tester);
    expect(find.text('•••• 4242'), findsOneWidget);
  });

  testWidgets('edits an address and cancel keeps remove dialog harmless', (
    tester,
  ) async {
    final fixture = _RouteFixture(initialLocation: settingsAddressesRoutePath);
    addTearDown(fixture.close);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-address-edit-shipping-home')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-address-street')),
      '99 Updated Street',
    );
    await tester.tap(find.byKey(const ValueKey('settings-address-save')));
    await _pumpNavigation(tester);
    expect(find.textContaining('99 Updated Street'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-address-remove-shipping-home')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-payment-remove-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-payment-remove-cancel')),
    );
    await _pumpNavigation(tester);
    expect(
      find.byKey(const ValueKey('settings-address-shipping-home')),
      findsOneWidget,
    );
  });

  testWidgets('card form remains reachable on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _RouteFixture(
      initialLocation: settingsAddPaymentMethodRoutePath,
      keyboardInset: 220,
      textScale: 1.6,
    );
    addTearDown(fixture.close);

    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-card-form')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-card-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card number and security code stay out of semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _RouteFixture(
      initialLocation: settingsAddPaymentMethodRoutePath,
    );
    addTearDown(fixture.close);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('settings-card-number')),
      '4242424242424242',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-card-security-code')),
      '123',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings-card-number')));
    await tester.pump();
    final numberNode = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Card number')),
    );
    expect(numberNode.value, isNot(contains('4242')));
    expect(
      numberNode.getSemanticsData().hasAction(SemanticsAction.setText),
      isTrue,
    );
    expect(
      numberNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('settings-card-security-code')));
    await tester.pump();
    final codeNode = tester.getSemantics(find.bySemanticsLabel(RegExp('CVV')));
    expect(codeNode.value, isNot(contains('123')));
    expect(
      codeNode.getSemanticsData().hasAction(SemanticsAction.setText),
      isTrue,
    );
    semantics.dispose();
  });
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

final class _RouteFixture {
  _RouteFixture({
    this.initialLocation = settingsPaymentMethodsRoutePath,
    this.keyboardInset = 0,
    this.textScale = 1,
  }) {
    final handler = SettingsPaymentFixtureHandler(paymentProfileStore: store);
    final dataSource = SettingsPaymentLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
      paymentProfileStore: store,
    );
    api = LocalSettingsPaymentAddressApi(dataSource: dataSource);
    router = GoRouter(
      initialLocation: initialLocation,
      routes: buildSettingsPaymentAddressRoutes(api: api),
    );
  }

  final String initialLocation;
  final double keyboardInset;
  final double textScale;
  final PaymentProfileStore store = PaymentProfileStore();
  late final LocalSettingsPaymentAddressApi api;
  late final GoRouter router;

  Widget app() => MaterialApp.router(
    routerConfig: router,
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: child!,
    ),
  );

  Future<void> close() async {
    router.dispose();
    await store.close();
  }
}
