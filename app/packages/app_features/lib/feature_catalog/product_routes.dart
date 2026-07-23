import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/cart_api.dart';
import '../api/catalog_api.dart';
import '../api/wishlist_api.dart';
import 'controllers/product_controller.dart';
import 'pages/product_detail_page.dart';

const productDetailRoutePath = '/products/:productId';

String productDetailLocation(String productId) =>
    '/products/${Uri.encodeComponent(productId)}';

String productReviewsLocation(String productId) =>
    '${productDetailLocation(productId)}/reviews';

/// 商品详情及评价的公开 Route 工厂，根壳工程负责把它装配到 Router。
List<RouteBase> buildProductRoutes({
  required ProductApi productApi,
  required WishlistApi wishlistApi,
  required CartApi cartApi,
}) => [
  GoRoute(
    path: productDetailRoutePath,
    builder: (context, state) {
      final productId = state.pathParameters['productId'];
      if (productId == null || productId.isEmpty) {
        return const _MissingProductRoute();
      }
      return ProductDetailPage(
        controller: ProductController(
          productApi: productApi,
          wishlistApi: wishlistApi,
          cartApi: cartApi,
          productId: productId,
        ),
        onOpenReviews: () => context.push('reviews'),
      );
    },
    routes: [
      GoRoute(
        path: 'reviews',
        builder: (context, state) {
          final productId = state.pathParameters['productId'];
          if (productId == null || productId.isEmpty) {
            return const _MissingProductRoute();
          }
          return ProductReviewsPage(
            controller: ProductController(
              productApi: productApi,
              wishlistApi: wishlistApi,
              cartApi: cartApi,
              productId: productId,
            ),
          );
        },
      ),
    ],
  ),
];

final class _MissingProductRoute extends StatelessWidget {
  const _MissingProductRoute();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Product not found'));
}
