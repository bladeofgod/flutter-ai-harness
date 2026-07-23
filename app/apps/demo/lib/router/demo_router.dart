import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state.dart';

GoRouter createDemoRouter({
  required FeaturesRegistry featuresRegistry,
  required AuthStateCoordinator authStateCoordinator,
  String initialLocation = welcomeRoutePath,
}) {
  final branchNavigatorKeys = List<GlobalKey<NavigatorState>>.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authStateCoordinator.authRefreshListenable,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isWelcome = location == welcomeRoutePath;
      final isMainApp = <String>[
        profileRoutePath,
        shopRoutePath,
        categoriesRoutePath,
        wishlistRoutePath,
        cartRoutePath,
        settingsRoutePath,
        '/products',
        '/checkout',
        searchRoutePath,
        flashSaleRoutePath,
        liveRoutePath,
        '/stories',
        rewardsRoutePath,
        vouchersRoutePath,
        supportRoutePath,
        settingsPaymentMethodsRoutePath,
        settingsAddressesRoutePath,
        activityRoutePath,
        ordersRoutePath,
      ].any((path) => location == path || location.startsWith('$path/'));
      final isAuth = location == '/auth' || location.startsWith('/auth/');

      if (!authStateCoordinator.isLoggedIn && isMainApp) {
        return welcomeRoutePath;
      }
      if (authStateCoordinator.isLoggedIn && (isWelcome || isAuth)) {
        return profileRoutePath;
      }
      return null;
    },
    routes: <RouteBase>[
      ...buildWelcomeRoutes(
        onGetStarted: (context) => context.go(registrationRoutePath),
        onSignIn: (context) => context.go(loginRoutePath),
      ),
      ...buildRegistrationRoutes(
        authApi: featuresRegistry.authApi,
        onAuthenticated: authStateCoordinator.authenticate,
        onCancel: (context) => context.go(welcomeRoutePath),
      ),
      ...buildLoginRoutes(
        authApi: featuresRegistry.authApi,
        onAuthenticated: authStateCoordinator.authenticate,
        onCancel: (context) => context.go(welcomeRoutePath),
      ),
      ...buildCheckoutRoutes(
        cartApi: featuresRegistry.cartApi,
        checkoutApi: featuresRegistry.checkoutApi,
        onEmptyCart: (context) => context.go(cartRoutePath),
        onCompleted: (context) => context.go(shopRoutePath),
        onReceiptReady: (receipt, cart) =>
            _acceptReceipt(featuresRegistry, receipt, cart),
      ),
      ...buildSearchRoutes(
        searchApi: featuresRegistry.searchApi,
        openProduct: (context, productId) =>
            unawaited(context.push(productDetailLocation(productId))),
      ),
      ...buildPromotionRoutes(
        promotionsApi: featuresRegistry.promotionsApi,
        onOpenProduct: (context, productId) =>
            unawaited(context.push(productDetailLocation(productId))),
        onExitStory: (context) => context.pop(),
      ),
      ...buildRewardsRoutes(
        rewardsApi: featuresRegistry.rewardsApi,
        onUseVoucher: (context, voucherId) =>
            unawaited(context.push(checkoutLocationWithVoucher(voucherId))),
      ),
      ...buildSupportRoutes(
        supportChatApi: featuresRegistry.supportChatApi,
        onOpenVoucher: (context, voucher) =>
            unawaited(context.push(vouchersRoutePath)),
      ),
      ...buildProductRoutes(
        productApi: featuresRegistry.productApi,
        wishlistApi: featuresRegistry.wishlistApi,
        cartApi: featuresRegistry.cartApi,
      ),
      ...buildSettingsPaymentAddressRoutes(
        api: featuresRegistry.settingsPaymentAddressApi,
      ),
      ...buildSettingsRoutes(
        settingsApi: featuresRegistry.settingsApi,
        currentUserProvider: authStateCoordinator,
        onUserUpdated: authStateCoordinator.updateCurrentUser,
        onDeleteAccount: authStateCoordinator.logout,
        openPaymentMethods: (context) =>
            unawaited(context.push(settingsPaymentMethodsRoutePath)),
        openAddresses: (context) =>
            unawaited(context.push(settingsAddressesRoutePath)),
      ),
      ...buildOrdersRoutes(
        ordersApi: featuresRegistry.ordersApi,
        currentUserProvider: authStateCoordinator,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ShoppeMainNavigationShell(
          currentIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            if (index == navigationShell.currentIndex) {
              navigationShell.goBranch(index, initialLocation: true);
            } else {
              navigationShell.goBranch(index);
            }
          },
          child: navigationShell,
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeys[0],
            routes: <RouteBase>[
              ...buildShopRoutes(
                catalogApi: featuresRegistry.catalogApi,
                openProduct: (context, productId) =>
                    unawaited(context.push(productDetailLocation(productId))),
                openSearch: (context) =>
                    unawaited(context.push(searchRoutePath)),
                openFlashSale: (context) =>
                    unawaited(context.push(flashSaleRoutePath)),
                openLive: (context) => unawaited(context.push(liveRoutePath)),
                openStory: (context) =>
                    unawaited(context.push(storyLocation('story-style-edit'))),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeys[1],
            routes: buildWishlistRoutes(
              wishlistApi: featuresRegistry.wishlistApi,
              productActions: WishlistProductActions(
                onAddItemToCart: (item) async {
                  await featuresRegistry.cartApi.upsert(
                    CartLineInput(
                      product: item.product,
                      variation: ProductVariation(
                        color: item.color,
                        size: item.size,
                      ),
                    ),
                  );
                },
              ),
              openProduct: (context, productId) =>
                  unawaited(context.push(productDetailLocation(productId))),
              openRecentlyViewed: (context) =>
                  context.go(recentlyViewedRoutePath),
            ),
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeys[2],
            routes: buildCategoriesRoutes(
              catalogApi: featuresRegistry.catalogBrowseApi,
              openProduct: (context, productId) =>
                  unawaited(context.push(productDetailLocation(productId))),
            ),
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeys[3],
            routes: <RouteBase>[
              ...buildCartRoutes(
                cartApi: featuresRegistry.cartApi,
                openCheckout: (context, cart) =>
                    unawaited(context.push(checkoutRoutePath)),
                openProduct: (context, productId) =>
                    unawaited(context.push(productDetailLocation(productId))),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeys[4],
            routes: <RouteBase>[
              ...buildProfileRoutes(
                profileDashboardApi: featuresRegistry.profileDashboardApi,
                currentUserProvider: authStateCoordinator,
                rewardsSummaryApi: featuresRegistry.rewardsApi,
                onOpenSettings: (context) =>
                    unawaited(context.push(settingsRoutePath)),
                onOpenActivity: (context) =>
                    unawaited(context.push(activityRoutePath)),
                onOpenRewards: (context) =>
                    unawaited(context.push(rewardsRoutePath)),
                onOpenSupport: (context) =>
                    unawaited(context.push(supportRoutePath)),
                onOpenOrderStatus: (context, status) => unawaited(
                  context.push(
                    status == OrderStatus.toReview
                        ? activityHistoryRoutePath
                        : activityRoutePath,
                  ),
                ),
                onOpenProduct: (context, productId) =>
                    unawaited(context.push(productDetailLocation(productId))),
                onOpenCategory: (context, categoryId) =>
                    context.go(categoriesRoutePath),
                onOpenStory: (context, story) => unawaited(
                  context.push(
                    story.isLive
                        ? liveRoutePath
                        : storyLocation('story-style-edit'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: SafeArea(child: Center(child: Text('Page not found'))),
    ),
  );
}

Future<void> _acceptReceipt(
  FeaturesRegistry featuresRegistry,
  CheckoutReceipt receipt,
  Cart cart,
) async {
  final lines = cart.items
      .map(
        (item) => OrderLine(
          product: item.product,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          variationLabel: '${item.variation.color}, ${item.variation.size}',
        ),
      )
      .toList(growable: false);
  await featuresRegistry.ordersApi.acceptReceipt(receipt, lines: lines);
  await featuresRegistry.settingsPaymentAddressApi.recordReceipt(receipt);
}
