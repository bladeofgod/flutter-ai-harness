import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/profile_dashboard_controller.dart';
import '../controllers/profile_rewards_summary_controller.dart';
import '../widgets/profile_components.dart';
import '../widgets/profile_memory_image.dart';

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

final class ProfileDashboardPage extends StatelessWidget {
  const ProfileDashboardPage({
    required this.controller,
    this.onOpenSettings,
    this.onOpenOrderStatus,
    this.onOpenActivity,
    this.onOpenRewards,
    this.onOpenSupport,
    this.onOpenProduct,
    this.onOpenCategory,
    this.onOpenStory,
    this.rewardsSummaryController,
    super.key,
  });

  final ProfileDashboardController controller;
  final VoidCallback? onOpenSettings;
  final ValueChanged<OrderStatus>? onOpenOrderStatus;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenRewards;
  final VoidCallback? onOpenSupport;
  final ValueChanged<String>? onOpenProduct;
  final ValueChanged<String>? onOpenCategory;
  final ValueChanged<Story>? onOpenStory;
  final ProfileRewardsSummaryController? rewardsSummaryController;

  @override
  Widget build(BuildContext context) => GetBuilder<ProfileDashboardController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final viewState = managedController.viewState;
          return switch (viewState) {
            ProfileDashboardLoading() => const _ProfileLoading(),
            ProfileDashboardData(:final dashboard) => _ProfileDashboardContent(
              controller: managedController,
              dashboard: dashboard,
              onOpenSettings: onOpenSettings,
              onOpenOrderStatus: onOpenOrderStatus,
              onOpenActivity: onOpenActivity,
              onOpenRewards: onOpenRewards,
              onOpenSupport: onOpenSupport,
              onOpenProduct: onOpenProduct,
              onOpenCategory: onOpenCategory,
              onOpenStory: onOpenStory,
              rewardsSummaryController: rewardsSummaryController,
            ),
            ProfileDashboardError(:final failure) => _ProfileError(
              failure: failure,
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(key: ValueKey('profile-loading')),
  );
}

final class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.failure, required this.onRetry});

  final ProfileDashboardFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: Color(0xFF697386),
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to load your profile',
            textAlign: TextAlign.center,
            style: _raleway(size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            'Please try again.',
            textAlign: TextAlign.center,
            style: _nunito(size: 14, color: const Color(0xFF697386)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('profile-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

final class _ProfileDashboardContent extends StatelessWidget {
  const _ProfileDashboardContent({
    required this.controller,
    required this.dashboard,
    this.onOpenSettings,
    this.onOpenOrderStatus,
    this.onOpenActivity,
    this.onOpenRewards,
    this.onOpenSupport,
    this.onOpenProduct,
    this.onOpenCategory,
    this.onOpenStory,
    this.rewardsSummaryController,
  });

  final ProfileDashboardController controller;
  final ProfileDashboard dashboard;
  final VoidCallback? onOpenSettings;
  final ValueChanged<OrderStatus>? onOpenOrderStatus;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenRewards;
  final VoidCallback? onOpenSupport;
  final ValueChanged<String>? onOpenProduct;
  final ValueChanged<String>? onOpenCategory;
  final ValueChanged<Story>? onOpenStory;
  final ProfileRewardsSummaryController? rewardsSummaryController;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('profile-dashboard-scroll'),
    slivers: [
      _ProfileSliver(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Obx(
          () => _ProfileHeader(
            user: controller.currentUser,
            onOpenSettings: onOpenSettings,
            onOpenActivity: onOpenActivity,
            onOpenRewards: onOpenRewards,
            onOpenSupport: onOpenSupport,
          ),
        ),
      ),
      if (dashboard.announcement case final announcement?) ...[
        _ProfileSliver(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _AnnouncementCard(announcement: announcement),
        ),
      ],
      if (rewardsSummaryController case final controller?)
        _ProfileSliver(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _ProfileRewardsSummary(
            controller: controller,
            onOpenRewards: onOpenRewards,
          ),
        ),
      _ProfileSliver(
        key: const ValueKey('profile-section-recently-viewed'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CatalogSectionHeader(title: 'Recently viewed'),
            const SizedBox(height: 10),
            _RecentlyViewedList(
              items: dashboard.recentlyViewed,
              onOpenProduct: onOpenProduct,
            ),
          ],
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-orders'),
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 0),
        child: _OrdersSection(
          summary: dashboard.orders,
          onOpenOrderStatus: onOpenOrderStatus,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-stories'),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
        child: _StoriesSection(
          stories: dashboard.stories,
          onOpenStory: onOpenStory,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-new-items'),
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
        child: _NewItemsSection(
          products: dashboard.newItems,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-most-popular'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: _MostPopularSection(
          products: dashboard.mostPopular,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-categories'),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
        child: _CategoriesSection(
          categories: dashboard.categories,
          onOpenCategory: onOpenCategory,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-flash-sale'),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
        child: _FlashSaleSection(
          flashSale: dashboard.flashSale,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-top-products'),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
        child: _TopProductsSection(
          products: dashboard.topProducts,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ProfileSliver(
        key: const ValueKey('profile-section-recommendations'),
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 28),
        child: _RecommendationsSection(
          products: dashboard.recommendations,
          onOpenProduct: onOpenProduct,
        ),
      ),
    ],
  );
}

final class _ProfileSliver extends StatelessWidget {
  const _ProfileSliver({required this.child, required this.padding, super.key});

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

final class _ProfileProductTapTarget extends StatelessWidget {
  const _ProfileProductTapTarget({
    required this.productId,
    required this.onOpenProduct,
    required this.child,
  });

  final String productId;
  final ValueChanged<String>? onOpenProduct;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onOpenProduct == null) {
      return child;
    }
    return InkWell(
      key: ValueKey<String>('profile-open-product-$productId'),
      borderRadius: BorderRadius.circular(9),
      onTap: () => onOpenProduct!(productId),
      child: child,
    );
  }
}

String _recentlyViewedProductId(String id) {
  final number = RegExp(r'\d+$').firstMatch(id)?.group(0);
  return number == null ? id : 'product-$number';
}

final class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    this.onOpenSettings,
    this.onOpenActivity,
    this.onOpenRewards,
    this.onOpenSupport,
  });

  final UserEntity? user;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenRewards;
  final VoidCallback? onOpenSupport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _UserAvatar(user: user),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              key: const ValueKey('profile-open-activity'),
              onTap: onOpenActivity,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'My Activity',
                    style: _raleway(
                      size: 16,
                      weight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          _HeaderIcon(
            key: const ValueKey('profile-open-rewards'),
            icon: Icons.card_giftcard_outlined,
            tooltip: 'Rewards',
            onTap: onOpenRewards,
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            key: const ValueKey('profile-open-support'),
            icon: Icons.chat_bubble_outline,
            tooltip: 'Support chat',
            onTap: onOpenSupport,
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            key: const ValueKey('profile-open-settings'),
            icon: Icons.settings_outlined,
            onTap: onOpenSettings,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        user == null ? 'Hello!' : 'Hello, ${user!.displayName}!',
        key: const ValueKey('profile-greeting'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _raleway(size: 28, height: 36 / 28),
      ),
    ],
  );
}

final class _ProfileRewardsSummary extends StatelessWidget {
  const _ProfileRewardsSummary({required this.controller, this.onOpenRewards});

  final ProfileRewardsSummaryController controller;
  final VoidCallback? onOpenRewards;

  @override
  Widget build(
    BuildContext context,
  ) => GetBuilder<ProfileRewardsSummaryController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Obx(() {
      final state = managedController.state;
      return switch (state) {
        ProfileRewardsSummaryLoading() => const SizedBox(
          key: ValueKey('profile-rewards-summary-loading'),
          height: 74,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        ProfileRewardsSummaryError() => const SizedBox.shrink(),
        ProfileRewardsSummaryData(:final summary) => Material(
          key: const ValueKey('profile-rewards-summary'),
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onOpenRewards,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 19,
                    backgroundColor: AppColors.primary,
                    child: Icon(
                      Icons.card_giftcard_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${summary.balance.availablePoints} reward points',
                          style: _raleway(size: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _profileRewardsSummaryLabel(summary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _nunito(
                            size: 12,
                            color: const Color(0xFF697386),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ),
      };
    }),
  );
}

String _profileRewardsSummaryLabel(RewardSummary summary) {
  final expiringVoucher = summary.expiringVoucher;
  return expiringVoucher == null
      ? '${summary.usableVoucherCount} vouchers available'
      : '${summary.usableVoucherCount} vouchers · '
            '${expiringVoucher.voucher.title} expires soon';
}

final class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, this.onTap, this.tooltip, super.key});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final iconButton = IconButton(
      tooltip: tooltip ?? (icon == Icons.settings_outlined ? 'Settings' : null),
      onPressed: onTap,
      icon: Icon(icon, size: 19, color: AppColors.primary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceMuted,
        shape: const CircleBorder(),
      ),
    );
    return SizedBox.square(dimension: 36, child: iconButton);
  }
}

final class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    final avatar = user?.avatar;
    final image = switch (avatar?.kind) {
      UserAvatarKind.asset when avatar?.assetKey != null => CatalogAssetImage(
        assetKey: avatar!.assetKey!,
      ),
      UserAvatarKind.memory when avatar?.bytes != null => ProfileMemoryImage(
        bytes: avatar!.bytes!,
      ),
      _ => const CatalogImagePlaceholder(),
    };

    return Semantics(
      label: user == null
          ? 'Profile avatar'
          : '${user!.displayName} profile avatar',
      image: true,
      child: SizedBox.square(
        key: const ValueKey('profile-avatar'),
        dimension: 44,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipOval(child: image),
          ),
        ),
      ),
    );
  }
}

final class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('profile-announcement'),
    constraints: const BoxConstraints(minHeight: 70),
    padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announcement.title,
                style: _raleway(size: 14, height: 18 / 14),
              ),
              const SizedBox(height: 2),
              Text(
                announcement.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _nunito(size: 10, height: 15 / 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.arrow_forward, size: 18, color: Colors.white),
        ),
      ],
    ),
  );
}

final class _RecentlyViewedList extends StatelessWidget {
  const _RecentlyViewedList({required this.items, this.onOpenProduct});

  final List<RecentlyViewed> items;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const CatalogEmptySection(label: 'No recently viewed items yet.');
    }
    return SizedBox(
      height: 60,
      child: ListView.separated(
        key: const ValueKey('profile-recently-viewed-list'),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final item = items[index];
          final child = Semantics(
            label: 'Recently viewed item ${index + 1}',
            image: true,
            child: SizedBox.square(
              dimension: 60,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: ClipOval(
                    child: CatalogAssetImage(assetKey: item.imageAssetKey),
                  ),
                ),
              ),
            ),
          );
          return _ProfileProductTapTarget(
            productId: _recentlyViewedProductId(item.id),
            onOpenProduct: onOpenProduct,
            child: child,
          );
        },
      ),
    );
  }
}

final class _OrdersSection extends StatelessWidget {
  const _OrdersSection({required this.summary, this.onOpenOrderStatus});

  final OrderSummary summary;
  final ValueChanged<OrderStatus>? onOpenOrderStatus;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'My Orders'),
      const SizedBox(height: 10),
      if (summary.items.isEmpty)
        const CatalogEmptySection(label: 'No order updates yet.')
      else
        Row(
          children: [
            for (var index = 0; index < summary.items.length; index += 1) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: _OrderPill(
                  item: summary.items[index],
                  onTap: onOpenOrderStatus == null
                      ? null
                      : () => onOpenOrderStatus!(summary.items[index].status),
                ),
              ),
            ],
          ],
        ),
    ],
  );
}

final class _OrderPill extends StatelessWidget {
  const _OrderPill({required this.item, this.onTap});

  final OrderStatusSummary item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (item.status) {
      OrderStatus.toPay => 'To Pay',
      OrderStatus.toReceive => 'To Receive',
      OrderStatus.toReview => 'To Review',
    };
    return Semantics(
      label: item.hasNotification ? '$label, new update' : label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            key: ValueKey<String>('profile-order-${item.status.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: _raleway(
                    size: 16,
                    weight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          if (item.hasNotification)
            const Positioned(
              right: -2,
              top: -2,
              child: CircleAvatar(
                radius: 5.5,
                backgroundColor: AppColors.success,
              ),
            ),
        ],
      ),
    );
  }
}

final class _StoriesSection extends StatelessWidget {
  const _StoriesSection({required this.stories, this.onOpenStory});

  final List<Story> stories;
  final ValueChanged<Story>? onOpenStory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'Stories'),
      const SizedBox(height: 9),
      if (stories.isEmpty)
        const CatalogEmptySection(label: 'No stories available.')
      else
        SizedBox(
          height: 175,
          child: ListView.separated(
            key: const ValueKey('profile-stories-list'),
            scrollDirection: Axis.horizontal,
            itemCount: stories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (context, index) => ProfileStoryCard(
              story: stories[index],
              onTap: onOpenStory == null
                  ? null
                  : () => onOpenStory!(stories[index]),
            ),
          ),
        ),
    ],
  );
}

final class _NewItemsSection extends StatelessWidget {
  const _NewItemsSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'New Items', showSeeAll: true),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No new items available.')
      else
        SizedBox(
          height: 218,
          child: ListView.separated(
            key: const ValueKey('profile-new-items-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 7),
            itemBuilder: (context, index) => _ProfileProductTapTarget(
              productId: products[index].id,
              onOpenProduct: onOpenProduct,
              child: CatalogProductCard(product: products[index]),
            ),
          ),
        ),
    ],
  );
}

final class _MostPopularSection extends StatelessWidget {
  const _MostPopularSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'Most Popular', showSeeAll: true),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No popular items available.')
      else
        SizedBox(
          height: 154,
          child: ListView.separated(
            key: const ValueKey('profile-most-popular-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 7),
            itemBuilder: (context, index) => _ProfileProductTapTarget(
              productId: products[index].id,
              onOpenProduct: onOpenProduct,
              child: CatalogPopularCard(product: products[index]),
            ),
          ),
        ),
    ],
  );
}

final class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({required this.categories, this.onOpenCategory});

  final List<CategorySummary> categories;
  final ValueChanged<String>? onOpenCategory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'Categories', showSeeAll: true),
      const SizedBox(height: 9),
      if (categories.isEmpty)
        const CatalogEmptySection(label: 'No categories available.')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: width,
                    height: 96,
                    child: ProfileCategoryCard(
                      category: category,
                      onTap: onOpenCategory == null
                          ? null
                          : () => onOpenCategory!(category.id),
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

final class _FlashSaleSection extends StatelessWidget {
  const _FlashSaleSection({required this.flashSale, this.onOpenProduct});

  final FlashSale flashSale;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Flash Sale',
              style: _raleway(size: 21, height: 30 / 21),
            ),
          ),
          const Icon(Icons.schedule, size: 18, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            flashSale.displayCountdown,
            key: const ValueKey('profile-flash-countdown'),
            style: _raleway(size: 14, weight: FontWeight.w600),
          ),
        ],
      ),
      const SizedBox(height: 9),
      if (flashSale.products.isEmpty)
        const CatalogEmptySection(label: 'No Flash Sale items available.')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final product in flashSale.products)
                  SizedBox.square(
                    dimension: width,
                    child: _ProfileProductTapTarget(
                      productId: product.id,
                      onOpenProduct: onOpenProduct,
                      child: CatalogSaleCard(product: product),
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

final class _TopProductsSection extends StatelessWidget {
  const _TopProductsSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'Top Products'),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No top products available.')
      else
        SizedBox(
          height: 88,
          child: ListView.separated(
            key: const ValueKey('profile-top-products-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 9),
            itemBuilder: (context, index) => _ProfileProductTapTarget(
              productId: products[index].id,
              onOpenProduct: onOpenProduct,
              child: CatalogTopProductCard(product: products[index]),
            ),
          ),
        ),
    ],
  );
}

final class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              'Just for You',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _raleway(size: 21, height: 30 / 21),
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.star, size: 14, color: AppColors.primary),
        ],
      ),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No recommendations available.')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final width = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: [
                for (final product in products)
                  SizedBox(
                    width: width,
                    height: 250,
                    child: _ProfileProductTapTarget(
                      productId: product.id,
                      onOpenProduct: onOpenProduct,
                      child: CatalogRecommendationCard(product: product),
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}
