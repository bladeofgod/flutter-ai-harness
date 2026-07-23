import 'package:app_data/app_data.dart';
import 'package:app_features/feature_catalog/controllers/product_controller.dart';
import 'package:app_features/feature_catalog/pages/product_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../feature_wishlist/wishlist_test_fixtures.dart';
import 'product_test_fixtures.dart';

void main() {
  testWidgets('renders gallery, Sale-independent detail and Reviews entry', (
    tester,
  ) async {
    final detail = productDetailFixture();
    final controller = _controller(detail);
    await tester.pumpWidget(
      MaterialApp(
        home: ProductDetailPage(controller: controller, onOpenReviews: () {}),
      ),
    );
    await _settleProduct(tester);

    expect(find.byKey(const ValueKey('product-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-description')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product-reviews-preview')),
      findsOneWidget,
    );
    expect(find.text(r'$17,00'), findsOneWidget);
    controller.onClose();
  });

  testWidgets(
    'variation sheet supports confirm and cancel without partial state',
    (tester) async {
      final controller = _controller(productDetailFixture());
      await tester.pumpWidget(
        MaterialApp(
          home: ProductDetailPage(controller: controller, onOpenReviews: () {}),
        ),
      );
      await _settleProduct(tester);

      final variationButton = find.byKey(
        const ValueKey('product-select-variation'),
      );
      for (var attempt = 0; attempt < 4; attempt += 1) {
        final rect = tester.getRect(variationButton);
        if (rect.top >= 0 && rect.bottom <= 600) {
          break;
        }
        await tester.drag(
          find.byKey(const ValueKey('product-detail-scroll')),
          const Offset(0, -220),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('product-select-variation')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('product-confirm-variation')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('product-option-color-pink')));
      await tester.tap(find.byKey(const ValueKey('product-option-size-m')));
      await tester.tap(find.byKey(const ValueKey('product-confirm-variation')));
      await tester.pumpAndSettle();
      expect(find.text('Options selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-select-variation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('product-cancel-variation')));
      await tester.pumpAndSettle();
      expect(find.text('Options selected'), findsOneWidget);
      controller.onClose();
    },
  );

  testWidgets('reviews page supports list and empty states', (tester) async {
    final controller = _controller(productDetailFixture());
    await tester.pumpWidget(
      MaterialApp(home: ProductReviewsPage(controller: controller)),
    );
    await _settleProduct(tester);
    expect(find.byKey(const ValueKey('reviews-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-review-1')), findsOneWidget);
    controller.onClose();

    final emptyController = _controller(
      productDetailFixture(emptyReviews: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProductReviewsPage(
          key: const ValueKey('empty-reviews-page'),
          controller: emptyController,
        ),
      ),
    );
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.byKey(const ValueKey('reviews-empty')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('reviews-empty')), findsOneWidget);
    emptyController.onClose();
  });
}

ProductController _controller(ProductDetail detail) => ProductController(
  productApi: FakeProductApi(detail: detail),
  wishlistApi: successfulWishlistApi(),
  cartApi: FakeProductCartApi(),
  productId: detail.product.id,
);

Future<void> _settleProduct(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byKey(const ValueKey('product-title')).evaluate().isNotEmpty ||
        find.byKey(const ValueKey('reviews-list')).evaluate().isNotEmpty ||
        find.byKey(const ValueKey('reviews-empty')).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Product page did not settle.');
}
