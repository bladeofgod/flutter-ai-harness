import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_media/app_media.dart';
import 'package:flutter/foundation.dart';

import 'api/auth_api.dart';
import 'api/cart_api.dart';
import 'api/catalog_api.dart';
import 'api/checkout_api.dart';
import 'api/order_review_media_api.dart';
import 'api/orders_api.dart';
import 'api/profile_dashboard_api.dart';
import 'api/promotions_api.dart';
import 'api/rewards_api.dart';
import 'api/search_api.dart';
import 'api/search_image_picker.dart';
import 'api/settings_api.dart';
import 'api/settings_payment_api.dart';
import 'api/support_chat_api.dart';
import 'api/support_media_picker.dart';
import 'api/wishlist_api.dart';
import 'feature_auth/api/local_auth_api.dart';
import 'feature_cart/api/local_cart_api.dart';
import 'feature_catalog/api/local_catalog_api.dart';
import 'feature_checkout/api/local_checkout_api.dart';
import 'feature_orders/api/local_orders_api.dart';
import 'feature_orders/api/native_order_review_media_api.dart';
import 'feature_profile/api/local_profile_dashboard_api.dart';
import 'feature_promotions/api/local_promotions_api.dart';
import 'feature_rewards/api/local_rewards_api.dart';
import 'feature_search/api/local_search_api.dart';
import 'feature_search/api/native_search_camera_media_picker.dart';
import 'feature_search/api/shared_media_search_image_picker.dart';
import 'feature_settings/api/local_settings_api.dart';
import 'feature_settings/api/local_settings_payment_api.dart';
import 'feature_support/api/local_support_chat_api.dart';
import 'feature_support/api/native_support_media_picker.dart';
import 'feature_wishlist/api/local_wishlist_api.dart';

/// 为 Demo 壳工程创建 Feature 依赖，隐藏具体 Feature 实现。
final class FeaturesRegistry {
  FeaturesRegistry._({
    required this.authApi,
    required this.cartApi,
    required this.catalogApi,
    required this.catalogBrowseApi,
    required this.checkoutApi,
    required this.productApi,
    required this.profileDashboardApi,
    required this.ordersApi,
    required this.orderReviewMediaApi,
    required this.promotionsApi,
    required this.rewardsApi,
    required this.searchApi,
    required this.searchImagePicker,
    required this.settingsApi,
    required this.settingsPaymentAddressApi,
    required this.supportChatApi,
    required this.supportMediaPicker,
    required this.mediaResourceStore,
    required bool ownsMediaResourceStore,
    required this.wishlistApi,
    required void Function() resetUserSession,
  }) : _resetUserSession = resetUserSession,
       _ownsMediaResourceStore = ownsMediaResourceStore;

  factory FeaturesRegistry.local({
    OrderReviewMediaApi? orderReviewMediaApi,
    SearchImagePicker? searchImagePicker,
    SupportMediaPicker? supportMediaPicker,
    MediaResourceStore? mediaResourceStore,
    Future<MediaResourceStore> Function()? mediaResourceStoreFactory,
  }) {
    assert(
      mediaResourceStore == null || mediaResourceStoreFactory == null,
      'Provide a media resource Store or a factory, not both.',
    );
    final resolvedMediaResourceStore =
        mediaResourceStore ??
        _DeferredMediaResourceStore(
          mediaResourceStoreFactory ?? createMediaResourceStore,
        );
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
    final mediaApi = orderReviewMediaApi ?? NativeOrderReviewMediaApi();
    final resolvedSearchImagePicker =
        searchImagePicker ??
        SharedMediaSearchImagePicker(
          cameraPicker: NativeSearchCameraMediaPicker(),
        );
    final resolvedSupportMediaPicker =
        supportMediaPicker ??
        NativeSupportMediaPicker(store: resolvedMediaResourceStore);
    final supportChatApi = LocalSupportChatApi(
      dataSource: supportDataSource,
      mediaResourceStore: resolvedMediaResourceStore,
    );

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
      orderReviewMediaApi: mediaApi,
      promotionsApi: LocalPromotionsApi(dataSource: promotionsDataSource),
      rewardsApi: LocalRewardsApi(dataSource: rewardsDataSource),
      searchApi: LocalSearchApi(dataSource: searchDataSource),
      searchImagePicker: resolvedSearchImagePicker,
      settingsApi: LocalSettingsApi(dataSource: settingsDataSource),
      settingsPaymentAddressApi: LocalSettingsPaymentAddressApi(
        dataSource: settingsPaymentDataSource,
      ),
      supportChatApi: supportChatApi,
      supportMediaPicker: resolvedSupportMediaPicker,
      mediaResourceStore: resolvedMediaResourceStore,
      ownsMediaResourceStore: mediaResourceStore == null,
      wishlistApi: LocalWishlistApi(dataSource: wishlistDataSource),
      resetUserSession: () {
        unawaited(_clearMediaDrafts(mediaApi));
        unawaited(_clearSearchMediaDrafts(resolvedSearchImagePicker));
        unawaited(
          _clearSupportSessionMedia(resolvedSupportMediaPicker, supportChatApi),
        );
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
  final OrderReviewMediaApi orderReviewMediaApi;
  final PromotionsApi promotionsApi;
  final RewardsApi rewardsApi;
  final SearchApi searchApi;
  final SearchImagePicker searchImagePicker;
  final SettingsApi settingsApi;
  final SettingsPaymentAddressApi settingsPaymentAddressApi;
  final SupportChatApi supportChatApi;
  final SupportMediaPicker supportMediaPicker;
  final MediaResourceStore mediaResourceStore;
  final WishlistApi wishlistApi;

  final void Function() _resetUserSession;
  final bool _ownsMediaResourceStore;
  Future<void>? _disposeFuture;

  void resetUserSession() => _resetUserSession();

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    unawaited(_completeDispose(completer));
    return completer.future;
  }

  Future<void> _completeDispose(Completer<void> completer) async {
    try {
      Object? firstError;
      StackTrace? firstStackTrace;
      Future<void> attempt(Future<void> Function() cleanup) async {
        try {
          await cleanup();
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }

      await attempt(orderReviewMediaApi.dispose);
      await attempt(searchImagePicker.dispose);
      await attempt(supportMediaPicker.dispose);
      await attempt(supportChatApi.dispose);
      if (_ownsMediaResourceStore) {
        await attempt(mediaResourceStore.dispose);
      }
      if (firstError case final error?) {
        Error.throwWithStackTrace(error, firstStackTrace!);
      }
      completer.complete();
    } on Object catch (error, stackTrace) {
      _disposeFuture = null;
      completer.completeError(error, stackTrace);
    }
  }
}

Future<void> _clearSupportSessionMedia(
  SupportMediaPicker mediaPicker,
  SupportChatApi supportChatApi,
) async {
  final sessionCleanup = _clearSupportApiSessionMedia(supportChatApi);
  try {
    await mediaPicker.clearDrafts();
  } on Object catch (_, stackTrace) {
    _reportMediaCleanupFailure(
      const SupportMediaPickerDisposalException(),
      'while clearing Support media drafts',
      stackTrace,
    );
  }
  await sessionCleanup;
}

Future<void> _clearSupportApiSessionMedia(SupportChatApi supportChatApi) async {
  try {
    await supportChatApi.clearSessionMedia();
  } on Object catch (_, stackTrace) {
    _reportMediaCleanupFailure(
      const SupportMediaPickerDisposalException(),
      'while clearing Support session media',
      stackTrace,
    );
  }
}

Future<void> _clearSearchMediaDrafts(SearchImagePicker imagePicker) async {
  try {
    await imagePicker.clearDrafts();
  } on Object catch (_, stackTrace) {
    _reportMediaCleanupFailure(
      const SearchImagePickerDisposalException(),
      'while clearing Search media drafts',
      stackTrace,
    );
  }
}

Future<void> _clearMediaDrafts(OrderReviewMediaApi mediaApi) async {
  try {
    await mediaApi.clearDrafts();
  } on Object catch (_, stackTrace) {
    _reportMediaCleanupFailure(
      const OrderReviewMediaDisposalException(),
      'while clearing Order Review media drafts',
      stackTrace,
    );
  }
}

void _reportMediaCleanupFailure(
  Object exception,
  String context,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: exception,
      stack: stackTrace,
      library: 'app_features',
      context: ErrorDescription(context),
    ),
  );
}

final class _DeferredMediaResourceStore implements MediaResourceStore {
  _DeferredMediaResourceStore(this._create);

  final Future<MediaResourceStore> Function() _create;
  Future<MediaResourceStore>? _delegate;
  Future<void>? _disposeFuture;
  bool _closed = false;

  Future<MediaResourceStore> _store() => _delegate ??= _create();

  @override
  Future<MediaImportResult> importFile(MediaImportRequest request) async {
    if (_closed) {
      return _storeClosed<OwnedMediaResource>();
    }
    return (await _store()).importFile(request);
  }

  @override
  Future<MediaResourceResult<MediaResourceLease>> retain(
    MediaResourceId resourceId,
  ) async {
    if (_closed) {
      return _storeClosed<MediaResourceLease>();
    }
    return (await _store()).retain(resourceId);
  }

  @override
  Future<MediaResourceResult<ResolvedMediaResource>> resolve(
    MediaResourceId resourceId,
    MediaResourceLease lease,
  ) async {
    if (_closed) {
      return _storeClosed<ResolvedMediaResource>();
    }
    return (await _store()).resolve(resourceId, lease);
  }

  @override
  Future<MediaResourceResult<void>> release(MediaResourceLease lease) async {
    final delegate = _delegate;
    if (delegate == null) {
      return _storeClosed<void>();
    }
    return (await delegate).release(lease);
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    final delegate = _delegate;
    return _disposeFuture = delegate == null
        ? Future<void>.value()
        : _disposeDelegate(delegate);
  }

  Future<void> _disposeDelegate(Future<MediaResourceStore> delegate) async {
    try {
      await (await delegate).dispose();
    } on Object {
      _disposeFuture = null;
      rethrow;
    }
  }
}

MediaResourceError<T> _storeClosed<T>() => MediaResourceError<T>(
  const MediaResourceFailure(
    code: MediaResourceFailureCode.storeClosed,
    isRecoverable: false,
  ),
);
