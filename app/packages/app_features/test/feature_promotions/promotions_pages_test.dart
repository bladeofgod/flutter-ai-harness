import 'package:app_features/feature_promotions/controllers/promotions_controllers.dart';
import 'package:app_features/feature_promotions/pages/flash_sale_page.dart';
import 'package:app_features/feature_promotions/pages/live_page.dart';
import 'package:app_features/feature_promotions/pages/story_page.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'promotions_test_fixtures.dart';

void main() {
  testWidgets('Flash Sale renders one scroll owner and fixed countdown', (
    tester,
  ) async {
    String? openedProduct;
    await _setViewport(tester, const Size(375, 812));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FlashSalePage(
          controller: FlashSaleController(promotionsApi: FakePromotionsApi()),
          onOpenProduct: (productId) => openedProduct = productId,
        ),
      ),
    );
    await _settle(tester, const ValueKey('flash-sale-scroll'));

    expect(find.text('00:36:58'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('flash-sale-scroll')),
        matching: find.byType(CustomScrollView),
      ),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('flash-sale-product-product-1')),
    );
    expect(openedProduct, 'product-1');
  });

  testWidgets(
    'Live exposes a truthful local preview state and product action',
    (tester) async {
      String? openedProduct;
      await _setViewport(tester, const Size(375, 812));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LivePage(
            controller: LiveController(promotionsApi: FakePromotionsApi()),
            onOpenProduct: (productId) => openedProduct = productId,
          ),
        ),
      );
      await _settle(tester, const ValueKey('live-prepare-preview'));

      expect(find.text('Prepare demo preview'), findsOneWidget);
      expect(find.textContaining('viewers'), findsNothing);
      expect(find.textContaining('Connected'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('live-prepare-preview')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Demo preview ready'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-open-product')));
      expect(openedProduct, 'product-1');
    },
  );

  testWidgets('Story navigation is manual and Variant driven', (tester) async {
    var closeCount = 0;
    String? openedProduct;
    final controller = StoryController(
      promotionsApi: FakePromotionsApi(),
      storyId: 'story-style-edit',
      onFinished: () => closeCount += 1,
    );
    await _setViewport(tester, const Size(375, 812));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StoryPage(
          controller: controller,
          onClose: () => closeCount += 1,
          onOpenProduct: (productId) => openedProduct = productId,
        ),
      ),
    );
    await _settle(tester, const ValueKey('story-next'));

    expect(find.text('Everyday color'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-open-product')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-open-product')));
    expect(openedProduct, 'product-2');

    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dress for your day'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-open-product')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Everyday color'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('story-next')));
    expect(closeCount, 1);
  });

  testWidgets(
    'Story and Live avoid overflow in compact, landscape and text scale',
    (tester) async {
      const cases = <({Size size, double textScale})>[
        (size: Size(320, 568), textScale: 1),
        (size: Size(812, 375), textScale: 1),
        (size: Size(375, 812), textScale: 1.3),
      ];

      for (final testCase in cases) {
        await tester.pumpWidget(const SizedBox());
        await _setViewport(tester, testCase.size);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
                textScaler: TextScaler.linear(testCase.textScale),
              ),
              child: child!,
            ),
            home: StoryPage(
              controller: StoryController(
                promotionsApi: FakePromotionsApi(),
                storyId: 'story-style-edit',
                onFinished: () {},
              ),
              onClose: () {},
              onOpenProduct: (_) {},
            ),
          ),
        );
        await _settle(tester, const ValueKey('story-next'));
        expect(tester.takeException(), isNull, reason: '${testCase.size}');

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
                textScaler: TextScaler.linear(testCase.textScale),
              ),
              child: child!,
            ),
            home: LivePage(
              controller: LiveController(promotionsApi: FakePromotionsApi()),
              onOpenProduct: (_) {},
            ),
          ),
        );
        await _settle(tester, const ValueKey('live-prepare-preview'));
        expect(tester.takeException(), isNull, reason: '${testCase.size} Live');
      }
    },
  );
}

Future<void> _settle(WidgetTester tester, ValueKey<String> key) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byKey(key).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Page did not settle for $key.');
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
