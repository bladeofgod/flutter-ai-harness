import 'package:app_data/app_data.dart';
import 'package:app_features/features_registry.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
