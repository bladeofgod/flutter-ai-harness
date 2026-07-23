import 'package:app_data/app_data.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/cart_api.dart';
import 'controllers/cart_controller.dart';
import 'pages/cart_page.dart';

const cartRoutePath = '/cart';

typedef CartCheckoutCallback = void Function(Cart cart);
typedef CartCheckoutNavigation = void Function(BuildContext context, Cart cart);
typedef CartProductNavigation =
    void Function(BuildContext context, String productId);

List<RouteBase> buildCartRoutes({
  required CartApi cartApi,
  CartCheckoutCallback? onCheckout,
  CartCheckoutNavigation? openCheckout,
  CartProductNavigation? openProduct,
}) => <RouteBase>[
  GoRoute(
    path: cartRoutePath,
    builder: (context, state) {
      final source = state.extra is CartRecommendationSource
          ? state.extra! as CartRecommendationSource
          : CartRecommendationSource.wishlist;
      final checkout = openCheckout == null
          ? onCheckout
          : (Cart cart) => openCheckout(context, cart);
      return CartPage(
        controller: CartController(
          cartApi: cartApi,
          recommendationSource: source,
        ),
        onCheckout: checkout,
        onOpenProduct: openProduct == null
            ? null
            : (productId) => openProduct(context, productId),
      );
    },
  ),
];
