import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';

import 'api/auth_api.dart';
import 'api/cart_api.dart';
import 'api/catalog_api.dart';
import 'api/checkout_api.dart';
import 'api/orders_api.dart';
import 'api/profile_dashboard_api.dart';
import 'api/promotions_api.dart';
import 'api/rewards_api.dart';
import 'api/search_api.dart';
import 'api/settings_api.dart';
import 'api/settings_payment_api.dart';
import 'api/support_chat_api.dart';
import 'api/wishlist_api.dart';
import 'feature_auth/api/local_auth_api.dart';
import 'feature_cart/api/local_cart_api.dart';
import 'feature_catalog/api/local_catalog_api.dart';
import 'feature_checkout/api/local_checkout_api.dart';
import 'feature_orders/api/local_orders_api.dart';
import 'feature_profile/api/local_profile_dashboard_api.dart';
import 'feature_promotions/api/local_promotions_api.dart';
import 'feature_rewards/api/local_rewards_api.dart';
import 'feature_search/api/local_search_api.dart';
import 'feature_settings/api/local_settings_api.dart';
import 'feature_settings/api/local_settings_payment_api.dart';
import 'feature_support/api/local_support_chat_api.dart';
import 'feature_wishlist/api/local_wishlist_api.dart';

/// 为 Demo 壳工程创建 Feature 依赖，隐藏具体 Feature 实现。
final class FeaturesRegistry {
  const FeaturesRegistry._({
    required this.authApi,
    required this.cartApi,
    required this.catalogApi,
    required this.catalogBrowseApi,
    required this.checkoutApi,
    required this.productApi,
    required this.profileDashboardApi,
    required this.ordersApi,
    required this.promotionsApi,
    required this.rewardsApi,
    required this.searchApi,
    required this.settingsApi,
    required this.settingsPaymentAddressApi,
    required this.supportChatApi,
    required this.wishlistApi,
    required void Function() resetUserSession,
  }) : _resetUserSession = resetUserSession;

  factory FeaturesRegistry.local() {
    final paymentProfileStore = PaymentProfileStore();
    final authHandler = AuthFixtureHandler();
    final cartHandler = CartFixtureHandler();
    final checkoutHandler = CheckoutFixtureHandler(
      paymentProfileStore: paymentProfileStore,
    );
    final ordersHandler = OrdersFixtureHandler();
    final rewardsHandler = RewardsFixtureHandler();
    final searchHandler = SearchFixtureHandler();
    final settingsHandler = SettingsFixtureHandler();
    final settingsPaymentHandler = SettingsPaymentFixtureHandler(
      paymentProfileStore: paymentProfileStore,
    );
    final supportHandler = SupportFixtureHandler();
    final wishlistHandler = WishlistFixtureHandler();
    final transport = FixtureApiTransport(
      handlers: <FixtureRequestHandler>[
        authHandler,
        cartHandler,
        checkoutHandler,
        ProfileDashboardFixtureHandler(),
        CatalogFixtureHandler(),
        ordersHandler,
        PromotionsFixtureHandler(),
        rewardsHandler,
        searchHandler,
        settingsHandler,
        settingsPaymentHandler,
        supportHandler,
        wishlistHandler,
      ],
    );
    final client = ApiClient(transport: transport);
    final authDataSource = AuthLocalDataSource(apiClient: client);
    final cartDataSource = CartLocalDataSource(apiClient: client);
    final catalogDataSource = CatalogLocalDataSource(apiClient: client);
    final profileDataSource = ProfileDashboardLocalDataSource(
      apiClient: client,
    );
    final settingsDataSource = SettingsLocalDataSource(apiClient: client);
    final checkoutDataSource = CheckoutLocalDataSource(
      apiClient: client,
      paymentProfileStore: paymentProfileStore,
    );
    final wishlistDataSource = WishlistLocalDataSource(apiClient: client);
    final ordersDataSource = OrdersLocalDataSource(apiClient: client);
    final promotionsDataSource = PromotionsLocalDataSource(apiClient: client);
    final rewardsDataSource = RewardsLocalDataSource(apiClient: client);
    final searchDataSource = SearchLocalDataSource(apiClient: client);
    final settingsPaymentDataSource = SettingsPaymentLocalDataSource(
      apiClient: client,
      paymentProfileStore: paymentProfileStore,
    );
    final supportDataSource = SupportLocalDataSource(apiClient: client);
    final catalogApi = LocalCatalogApi(dataSource: catalogDataSource);

    return FeaturesRegistry._(
      authApi: LocalAuthApi(dataSource: authDataSource),
      cartApi: LocalCartApi(dataSource: cartDataSource),
      catalogApi: catalogApi,
      catalogBrowseApi: catalogApi,
      checkoutApi: LocalCheckoutApi(dataSource: checkoutDataSource),
      productApi: catalogApi,
      profileDashboardApi: LocalProfileDashboardApi(
        dataSource: profileDataSource,
      ),
      ordersApi: LocalOrdersApi(dataSource: ordersDataSource),
      promotionsApi: LocalPromotionsApi(dataSource: promotionsDataSource),
      rewardsApi: LocalRewardsApi(dataSource: rewardsDataSource),
      searchApi: LocalSearchApi(dataSource: searchDataSource),
      settingsApi: LocalSettingsApi(dataSource: settingsDataSource),
      settingsPaymentAddressApi: LocalSettingsPaymentAddressApi(
        dataSource: settingsPaymentDataSource,
      ),
      supportChatApi: LocalSupportChatApi(dataSource: supportDataSource),
      wishlistApi: LocalWishlistApi(dataSource: wishlistDataSource),
      resetUserSession: () {
        cartHandler.resetSession();
        checkoutHandler.resetSession();
        ordersHandler.resetSession();
        rewardsHandler.resetSession();
        settingsHandler.resetSession();
        settingsPaymentHandler.resetSession();
        supportHandler.resetSession();
        wishlistHandler.resetSession();
      },
    );
  }

  final AuthApi authApi;
  final CartApi cartApi;
  final CatalogApi catalogApi;
  final CatalogBrowseApi catalogBrowseApi;
  final CheckoutApi checkoutApi;
  final ProductApi productApi;
  final ProfileDashboardApi profileDashboardApi;
  final OrdersApi ordersApi;
  final PromotionsApi promotionsApi;
  final RewardsApi rewardsApi;
  final SearchApi searchApi;
  final SettingsApi settingsApi;
  final SettingsPaymentAddressApi settingsPaymentAddressApi;
  final SupportChatApi supportChatApi;
  final WishlistApi wishlistApi;

  final void Function() _resetUserSession;

  void resetUserSession() => _resetUserSession();
}
