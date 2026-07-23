import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders five semantic destinations and reports taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selectedIndex = -1;
    await _pumpShell(
      tester,
      currentIndex: 2,
      onDestinationSelected: (index) => selectedIndex = index,
    );

    expect(
      find.byKey(const ValueKey('main-bottom-navigation')),
      findsOneWidget,
    );
    for (final label in <String>[
      'Shop',
      'Wishlist',
      'Categories',
      'Cart',
      'Profile',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    final categories = tester.getSemantics(find.bySemanticsLabel('Categories'));
    expect(categories.flagsCollection.isSelected, isTrue);

    await tester.tap(find.byKey(const ValueKey('main-navigation-profile')));
    expect(selectedIndex, 4);
    semantics.dispose();
  });

  testWidgets('keeps a fixed 50 logical pixel bar above the safe area', (
    tester,
  ) async {
    await _pumpShell(tester, bottomInset: 34);

    final bar = tester.getRect(
      find.byKey(const ValueKey('main-bottom-navigation')),
    );
    expect(bar.height, 50);
    expect(find.text('Branch content'), findsOneWidget);
  });

  testWidgets('does not overflow compact, landscape, or scaled layouts', (
    tester,
  ) async {
    const cases = <({Size size, double textScale, double bottomInset})>[
      (size: Size(320, 568), textScale: 1, bottomInset: 24),
      (size: Size(812, 375), textScale: 1, bottomInset: 0),
      (size: Size(375, 812), textScale: 1.3, bottomInset: 34),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpShell(
        tester,
        textScale: testCase.textScale,
        bottomInset: testCase.bottomInset,
      );
      expect(tester.takeException(), isNull, reason: '${testCase.size}');
    }
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  int currentIndex = 0,
  ValueChanged<int>? onDestinationSelected,
  double textScale = 1,
  double bottomInset = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize,
          devicePixelRatio: 1,
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ShoppeMainNavigationShell(
          currentIndex: currentIndex,
          onDestinationSelected: onDestinationSelected ?? (_) {},
          child: const Center(child: Text('Branch content')),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
