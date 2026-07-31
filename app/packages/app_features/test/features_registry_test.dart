import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/search_image_picker.dart';
import 'package:app_features/api/support_media_picker.dart';
import 'package:app_features/features_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'feature_orders/orders_test_fixtures.dart';
import 'feature_support/support_test_fixtures.dart';

void main() {
  test('resetUserSession restores mutable local feature state', () async {
    final registry = FeaturesRegistry.local();
    final initialSettings = await registry.settingsApi.load();
    final initialPayment = await registry.settingsPaymentAddressApi.load();

    await registry.cartApi.upsert(
      CartLineInput(
        product: ProductSummary(
          id: 'product-31',
          title: 'Session-only product',
          imageAssetKey: 'assets/images/profile/product_11.png',
          price: Money(currency: Currency.usd, minorUnits: 1900),
        ),
        variation: ProductVariation(color: 'Black', size: 'L'),
      ),
    );
    await registry.wishlistApi.removeWishlistItem('product-1');
    await registry.settingsApi.updatePreferences(
      initialSettings.copyWith(notificationsEnabled: false),
    );
    await registry.settingsPaymentAddressApi.removePaymentMethod(
      initialPayment.paymentProfile.paymentMethods.first.id,
    );
    final rewards = await registry.rewardsApi.load();
    final reminder = rewards.vouchers.firstWhere(
      (voucher) =>
          voucher.lifecycle == VoucherLifecycle.expiringSoon &&
          !voucher.reminderConsumed,
    );
    await registry.rewardsApi.consumeReminder(voucherId: reminder.voucher.id);
    await registry.ordersApi.submitReview(
      orderId: 'order-1003',
      rating: 5,
      comment: 'Session-only review.',
      author: 'Session User',
    );

    registry.resetUserSession();

    final cart = await registry.cartApi.load();
    final wishlist = await registry.wishlistApi.loadWishlist();
    final settings = await registry.settingsApi.load();
    final payment = await registry.settingsPaymentAddressApi.load();
    final resetRewards = await registry.rewardsApi.load();
    final order = await registry.ordersApi.loadOrder(orderId: 'order-1003');

    expect(cart.items, hasLength(2));
    expect(wishlist.items, hasLength(5));
    expect(settings, initialSettings);
    expect(
      payment.paymentProfile.addresses.map((address) => address.id),
      initialPayment.paymentProfile.addresses.map((address) => address.id),
    );
    expect(
      payment.paymentProfile.paymentMethods.map((method) => method.id),
      initialPayment.paymentProfile.paymentMethods.map((method) => method.id),
    );
    expect(payment.receipts, isEmpty);
    expect(
      resetRewards.vouchers
          .firstWhere((voucher) => voucher.voucher.id == reminder.voucher.id)
          .reminderConsumed,
      isFalse,
    );
    expect(order.review, isNull);
  });

  test('owns one media API and disposes it exactly once', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final searchPicker = _TrackingSearchImagePicker();
    final supportPicker = _TrackingSupportMediaPicker();
    final mediaResourceStore = TestSupportMediaResourceStore();
    final registry = FeaturesRegistry.local(
      orderReviewMediaApi: mediaApi,
      searchImagePicker: searchPicker,
      supportMediaPicker: supportPicker,
      mediaResourceStore: mediaResourceStore,
    );

    expect(registry.orderReviewMediaApi, same(mediaApi));
    expect(registry.searchImagePicker, same(searchPicker));
    expect(registry.supportMediaPicker, same(supportPicker));
    registry.resetUserSession();
    await Future<void>.delayed(Duration.zero);
    expect(mediaApi.clearCount, 1);
    expect(searchPicker.clearCount, 1);
    expect(supportPicker.clearCount, 1);

    await registry.dispose();
    await registry.dispose();
    expect(mediaApi.disposeCount, 1);
    expect(searchPicker.disposeCount, 1);
    expect(supportPicker.disposeCount, 1);
    expect(mediaResourceStore.disposeCount, 0);
  });

  test('creates and disposes an internally owned media Store once', () async {
    final mediaResourceStore = TestSupportMediaResourceStore();
    var createCount = 0;
    final registry = FeaturesRegistry.local(
      mediaResourceStoreFactory: () async {
        createCount += 1;
        return mediaResourceStore;
      },
    );

    await registry.mediaResourceStore.retain(
      MediaResourceId('mr_00000000000000000000000000000001'),
    );
    await registry.dispose();
    await registry.dispose();

    expect(createCount, 1);
    expect(mediaResourceStore.disposeCount, 1);
  });

  test('retries aggregate disposal after a cleanup failure', () async {
    final searchPicker = _TrackingSearchImagePicker()
      ..disposeResults.addAll(<bool>[false, true]);
    final registry = FeaturesRegistry.local(
      orderReviewMediaApi: FakeOrderReviewMediaApi(),
      searchImagePicker: searchPicker,
    );

    await expectLater(
      registry.dispose(),
      throwsA(isA<SearchImagePickerDisposalException>()),
    );
    await registry.dispose();

    expect(searchPicker.disposeCount, 2);
  });

  test('reports reset cleanup failures with redacted diagnostics', () async {
    final previousHandler = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousHandler);
    final searchPicker = _TrackingSearchImagePicker()..throwOnClear = true;
    final registry = FeaturesRegistry.local(
      orderReviewMediaApi: FakeOrderReviewMediaApi(),
      searchImagePicker: searchPicker,
    );

    registry.resetUserSession();
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<SearchImagePickerDisposalException>());
    expect(errors.single.stack, isNotNull);
    expect(errors.single.exceptionAsString(), isNot(contains('secret-handle')));
  });
}

final class _TrackingSearchImagePicker implements SearchImagePicker {
  var clearCount = 0;
  var disposeCount = 0;
  var throwOnClear = false;
  final List<bool> disposeResults = <bool>[];

  @override
  Future<SearchImagePickResult> capturePhoto() async =>
      const SearchImagePickCanceled();

  @override
  Future<SearchImagePickResult> pickFromGallery() async =>
      const SearchImagePickCanceled();

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
    if (throwOnClear) {
      throw StateError('secret-handle');
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    final succeeds = disposeResults.isEmpty ? true : disposeResults.removeAt(0);
    if (!succeeds) {
      throw const SearchImagePickerDisposalException();
    }
  }
}

final class _TrackingSupportMediaPicker implements SupportMediaPicker {
  var clearCount = 0;
  var disposeCount = 0;

  @override
  Future<SupportMediaPickResult> pick(SupportMediaSource source) async =>
      const SupportMediaPickCanceled();

  @override
  Future<void> release(SupportMediaAttachment attachment) async {}

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
