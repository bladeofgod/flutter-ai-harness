import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/wishlist_api.dart';
import 'controllers/recently_viewed_controller.dart';
import 'controllers/wishlist_controller.dart';
import 'pages/recently_viewed_page.dart';
import 'pages/wishlist_page.dart';

const wishlistRoutePath = '/wishlist';
const recentlyViewedRoutePath = '/wishlist/recently-viewed';

typedef WishlistProductNavigation =
    void Function(BuildContext context, String productId);

List<RouteBase> buildWishlistRoutes({
  required WishlistApi wishlistApi,
  WishlistProductActions productActions = const WishlistProductActions(),
  void Function(BuildContext context)? openRecentlyViewed,
  WishlistProductNavigation? openProduct,
}) => <RouteBase>[
  GoRoute(
    path: wishlistRoutePath,
    builder: (context, state) => WishlistPage(
      controller: WishlistController(wishlistApi: wishlistApi),
      onOpenRecentlyViewed: () {
        if (openRecentlyViewed case final open?) {
          open(context);
        } else {
          unawaited(context.push(recentlyViewedRoutePath));
        }
      },
      productActions: openProduct == null
          ? productActions
          : WishlistProductActions(
              onOpenProduct: (productId) => openProduct(context, productId),
              onAddToCart: productActions.onAddToCart,
              onAddItemToCart: productActions.onAddItemToCart,
              onSeeAllRecommendations: productActions.onSeeAllRecommendations,
            ),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: 'recently-viewed',
        builder: (context, state) {
          final resolvedActions = openProduct == null
              ? productActions
              : WishlistProductActions(
                  onOpenProduct: (productId) => openProduct(context, productId),
                  onAddToCart: productActions.onAddToCart,
                  onAddItemToCart: productActions.onAddItemToCart,
                  onSeeAllRecommendations:
                      productActions.onSeeAllRecommendations,
                );
          return RecentlyViewedPage(
            controller: RecentlyViewedController(wishlistApi: wishlistApi),
            productActions: resolvedActions,
          );
        },
      ),
    ],
  ),
];
