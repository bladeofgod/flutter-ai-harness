import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/catalog_api.dart';
import 'controllers/shop_dashboard_controller.dart';
import 'pages/shop_dashboard_page.dart';

export 'product_routes.dart'
    show
        buildProductRoutes,
        productDetailLocation,
        productDetailRoutePath,
        productReviewsLocation;

const shopRoutePath = '/shop';

typedef ShopProductNavigation =
    void Function(BuildContext context, String productId);
typedef ShopPageNavigation = void Function(BuildContext context);

List<RouteBase> buildShopRoutes({
  required CatalogApi catalogApi,
  ShopProductNavigation? openProduct,
  ShopPageNavigation? openSearch,
  ShopPageNavigation? openFlashSale,
  ShopPageNavigation? openLive,
  ShopPageNavigation? openStory,
}) => [
  GoRoute(
    path: shopRoutePath,
    builder: (context, state) => ShopDashboardPage(
      controller: ShopDashboardController(catalogApi: catalogApi),
      onOpenProduct: openProduct == null
          ? null
          : (productId) => openProduct(context, productId),
      onOpenSearch: openSearch == null ? null : () => openSearch(context),
      onOpenFlashSale: openFlashSale == null
          ? null
          : () => openFlashSale(context),
      onOpenLive: openLive == null ? null : () => openLive(context),
      onOpenStory: openStory == null ? null : () => openStory(context),
    ),
  ),
];
