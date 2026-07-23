import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../api/cart_api.dart';
import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../cart_demo_recommendations.dart';
import '../controllers/cart_controller.dart';
import '../routes.dart';

const _contentMaxWidth = 420.0;

TextStyle _raleway({
  required double size,
  FontWeight weight = FontWeight.w700,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

TextStyle _nunito({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

final class CartPage extends StatelessWidget {
  const CartPage({
    required this.controller,
    this.onCheckout,
    this.onOpenProduct,
    super.key,
  });

  final CartController controller;
  final CartCheckoutCallback? onCheckout;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => GetBuilder<CartController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: true,
        child: Obx(() {
          final state = managedController.viewState;
          return switch (state) {
            CartLoading() => const Center(
              child: CircularProgressIndicator(key: ValueKey('cart-loading')),
            ),
            CartData(:final cart, :final isMutating) => _CartContent(
              cart: cart,
              source: CartRecommendationSource.wishlist,
              isMutating: isMutating,
              controller: managedController,
              onCheckout: onCheckout,
              onOpenProduct: onOpenProduct,
            ),
            CartEmpty(:final cart, :final source, :final isMutating) =>
              _CartContent(
                cart: cart,
                source: source,
                isMutating: isMutating,
                controller: managedController,
                onCheckout: onCheckout,
                onOpenProduct: onOpenProduct,
              ),
            CartError() => _CartError(onRetry: managedController.retryFromUi),
          };
        }),
      ),
    ),
  );
}

final class _CartContent extends StatelessWidget {
  const _CartContent({
    required this.cart,
    required this.source,
    required this.isMutating,
    required this.controller,
    required this.onCheckout,
    this.onOpenProduct,
  });

  final Cart cart;
  final CartRecommendationSource source;
  final bool isMutating;
  final CartController controller;
  final CartCheckoutCallback? onCheckout;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          key: const ValueKey('cart-scroll'),
          slivers: [
            _CartSliver(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: _CartHeader(quantity: cart.totalQuantity),
            ),
            const _CartSliver(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _ShippingAddress(),
            ),
            if (cart.isEmpty)
              const _CartSliver(
                padding: EdgeInsets.fromLTRB(20, 60, 20, 0),
                child: _CartEmptyIllustration(),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _sidePadding(context),
                  16,
                  _sidePadding(context),
                  0,
                ),
                sliver: SliverList.separated(
                  itemCount: cart.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return _CartItemCard(
                      item: item,
                      enabled: !isMutating,
                      onIncrement: () => controller.incrementFromUi(item.id),
                      onDecrement: () => controller.decrementFromUi(item.id),
                      onRemove: () => controller.removeFromUi(item.id),
                      onOpenProduct: onOpenProduct == null
                          ? null
                          : () => onOpenProduct!(item.product.id),
                    );
                  },
                ),
              ),
            _CartSliver(
              padding: EdgeInsets.fromLTRB(20, cart.isEmpty ? 76 : 22, 20, 28),
              child: _Recommendations(
                source: source,
                enabled: !isMutating,
                onAddToCart: controller.addRecommendationFromUi,
              ),
            ),
          ],
        ),
      ),
      _CheckoutBar(
        cart: cart,
        enabled: !cart.isEmpty && !isMutating && onCheckout != null,
        onCheckout: onCheckout,
      ),
    ],
  );
}

double _sidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > _contentMaxWidth ? (width - _contentMaxWidth) / 2 + 20 : 20;
}

final class _CartSliver extends StatelessWidget {
  const _CartSliver({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

final class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('Cart', style: _raleway(size: 28, height: 36 / 28)),
      const SizedBox(width: 9),
      Container(
        key: const ValueKey('cart-quantity-badge'),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.primarySurface,
          shape: BoxShape.circle,
        ),
        child: Text('$quantity', style: _raleway(size: 18)),
      ),
    ],
  );
}

final class _ShippingAddress extends StatelessWidget {
  const _ShippingAddress();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('cart-shipping-address'),
    constraints: const BoxConstraints(minHeight: 70),
    padding: const EdgeInsets.fromLTRB(16, 9, 12, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF9F9F9),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shipping Address', style: _raleway(size: 14)),
              const SizedBox(height: 3),
              Text(
                '26, Duong So 2, Thao Dien Ward, An Phu, District 2, '
                'Ho Chi Minh city',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _nunito(size: 10, height: 15 / 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.edit, color: Colors.white, size: 16),
        ),
      ],
    ),
  );
}

final class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.onOpenProduct,
  });

  final CartItem item;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback? onOpenProduct;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey<String>('cart-item-${item.id}'),
    height: _responsiveRowHeight(context, 107),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 126,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: InkWell(
                  key: ValueKey<String>('cart-open-product-${item.product.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: onOpenProduct,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Color(0x22000000), blurRadius: 7),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CatalogAssetImage(
                          assetKey: item.product.imageAssetKey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: _RoundAction(
                  key: ValueKey<String>('cart-remove-${item.id}'),
                  label: 'Remove ${item.product.title}',
                  icon: Icons.delete_outline,
                  color: const Color(0xFFFF6B73),
                  background: Colors.white,
                  onPressed: enabled ? onRemove : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _nunito(size: 12, height: 16 / 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.variation.color}, Size ${item.variation.size}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _raleway(size: 14, weight: FontWeight.w500),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.unitPrice.format(),
                      maxLines: 1,
                      style: _raleway(size: 18),
                    ),
                  ),
                  _RoundAction(
                    key: ValueKey<String>('cart-decrement-${item.id}'),
                    label: 'Decrease ${item.product.title} quantity',
                    icon: Icons.remove,
                    onPressed: enabled && item.quantity > 1
                        ? onDecrement
                        : null,
                  ),
                  Container(
                    key: ValueKey<String>('cart-item-quantity-${item.id}'),
                    width: 38,
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('${item.quantity}', style: _raleway(size: 16)),
                  ),
                  _RoundAction(
                    key: ValueKey<String>('cart-increment-${item.id}'),
                    label: 'Increase ${item.product.title} quantity',
                    icon: Icons.add,
                    onPressed: enabled ? onIncrement : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.color = AppColors.primary,
    this.background = Colors.white,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final foreground = onPressed == null
        ? color.withValues(alpha: 0.35)
        : color;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 20,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          maximumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: foreground, width: 2),
          ),
          child: SizedBox.square(
            dimension: 30,
            child: Icon(icon, color: foreground, size: 20),
          ),
        ),
      ),
    );
  }
}

final class _CartEmptyIllustration extends StatelessWidget {
  const _CartEmptyIllustration();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      key: const ValueKey('cart-empty-illustration'),
      width: 134,
      height: 134,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 7,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: 58,
          height: 61,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: SvgPicture.asset(
                  'assets/images/cart/empty_bag_body.svg',
                  package: 'app_features',
                ),
              ),
              Positioned(
                top: 0,
                width: 35,
                height: 29,
                child: SvgPicture.asset(
                  'assets/images/cart/empty_bag_handle.svg',
                  package: 'app_features',
                ),
              ),
              Positioned(
                top: 0,
                width: 35,
                height: 17,
                child: SvgPicture.asset(
                  'assets/images/cart/empty_bag_handle_inner.svg',
                  package: 'app_features',
                ),
              ),
              Positioned(
                bottom: 7,
                width: 12,
                height: 20,
                child: SvgPicture.asset(
                  'assets/images/cart/empty_bag_mark.svg',
                  package: 'app_features',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _Recommendations extends StatelessWidget {
  const _Recommendations({
    required this.source,
    required this.enabled,
    required this.onAddToCart,
  });

  final CartRecommendationSource source;
  final bool enabled;
  final ValueChanged<ProductSummary> onAddToCart;

  @override
  Widget build(BuildContext context) {
    final products = cartRecommendations(source);
    return switch (source) {
      CartRecommendationSource.wishlist => Column(
        key: const ValueKey('cart-recommendations-wishlist'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('From Your Wishlist', style: _raleway(size: 22)),
          const SizedBox(height: 16),
          for (var index = 0; index < products.length; index += 1) ...[
            _WishlistRecommendation(
              product: products[index],
              enabled: enabled,
              onAddToCart: () => onAddToCart(products[index]),
            ),
            if (index != products.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
      CartRecommendationSource.popular => Column(
        key: const ValueKey('cart-recommendations-popular'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CatalogSectionHeader(
            title: 'Most Popular',
            showSeeAll: true,
            actionTextSize: 15,
            actionRadius: 15,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              key: const ValueKey('cart-popular-list'),
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) => CatalogPopularCard(
                product: products[index],
                countSize: 15,
                tagSize: 13,
                borderRadius: 8,
                imageHeight: 103,
                imagePadding: const EdgeInsets.all(4),
                frameImage: true,
                showFavorite: true,
              ),
            ),
          ),
        ],
      ),
    };
  }
}

final class _WishlistRecommendation extends StatelessWidget {
  const _WishlistRecommendation({
    required this.product,
    required this.enabled,
    required this.onAddToCart,
  });

  final ProductSummary product;
  final bool enabled;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _responsiveRowHeight(context, 123),
    child: Row(
      children: [
        Container(
          width: 126,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 7),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CatalogAssetImage(assetKey: product.imageAssetKey),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _nunito(size: 12, height: 16 / 12),
              ),
              const Spacer(),
              Text(product.price!.format(), style: _raleway(size: 18)),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Flexible(child: _VariationChip(label: 'Pink')),
                  const SizedBox(width: 4),
                  const Flexible(child: _VariationChip(label: 'M')),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Add to cart',
                    child: InkResponse(
                      key: ValueKey<String>(
                        'cart-add-recommendation-${product.id}',
                      ),
                      onTap: enabled ? onAddToCart : null,
                      radius: 18,
                      child: const SizedBox.square(
                        dimension: 30,
                        child: Icon(
                          Icons.add_shopping_cart_outlined,
                          color: AppColors.primary,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _VariationChip extends StatelessWidget {
  const _VariationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 25,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, style: _raleway(size: 14, weight: FontWeight.w500)),
    ),
  );
}

double _responsiveRowHeight(BuildContext context, double baseHeight) {
  final scaledUnit = MediaQuery.textScalerOf(context).scale(16);
  return baseHeight + (scaledUnit - 16).clamp(0, 12) * 2;
}

final class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.cart,
    required this.enabled,
    required this.onCheckout,
  });

  final Cart cart;
  final bool enabled;
  final CartCheckoutCallback? onCheckout;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('cart-checkout-bar'),
    color: const Color(0xFFF5F5F5),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Total',
                  style: _raleway(size: 20, weight: FontWeight.w800),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    cart.total.format(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _raleway(size: 18),
                  ),
                ),
                SizedBox(
                  width: 128,
                  height: 40,
                  child: FilledButton(
                    key: const ValueKey('cart-checkout'),
                    onPressed: enabled ? () => onCheckout!(cart) : null,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: Text(
                      'Checkout',
                      maxLines: 1,
                      style: _nunito(
                        size: 16,
                        color: enabled ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _CartError extends StatelessWidget {
  const _CartError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_bag_outlined,
            size: 42,
            color: Color(0xFF697386),
          ),
          const SizedBox(height: 12),
          Text('Unable to load the cart', style: _raleway(size: 20)),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('cart-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
