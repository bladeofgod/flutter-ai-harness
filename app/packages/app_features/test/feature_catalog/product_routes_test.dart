import 'package:app_features/feature_catalog/product_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../feature_wishlist/wishlist_test_fixtures.dart';
import 'product_test_fixtures.dart';

void main() {
  testWidgets('Product detail and Reviews share one detail route family', (
    tester,
  ) async {
    final detail = productDetailFixture();
    final router = GoRouter(
      initialLocation: productDetailLocation(detail.product.id),
      routes: buildProductRoutes(
        productApi: FakeProductApi(detail: detail),
        wishlistApi: successfulWishlistApi(),
        cartApi: FakeProductCartApi(),
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester, const ValueKey('product-title'));
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      productDetailLocation(detail.product.id),
    );

    router.go(productReviewsLocation(detail.product.id));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      productReviewsLocation(detail.product.id),
    );
    expect(find.byKey(const ValueKey('reviews-list')), findsOneWidget);
  });
}

Future<void> _settle(WidgetTester tester, ValueKey<String> key) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byKey(key).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Route did not settle.');
}
