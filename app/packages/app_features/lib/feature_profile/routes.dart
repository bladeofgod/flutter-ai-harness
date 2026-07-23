import 'package:app_data/app_data.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/current_user_provider.dart';
import '../api/profile_dashboard_api.dart';
import '../api/rewards_api.dart';
import 'controllers/profile_dashboard_controller.dart';
import 'controllers/profile_rewards_summary_controller.dart';
import 'pages/profile_dashboard_page.dart';

const profileRoutePath = '/profile';

typedef ProfileSettingsNavigation = void Function(BuildContext context);
typedef ProfileOrderNavigation =
    void Function(BuildContext context, OrderStatus status);
typedef ProfileActivityNavigation = void Function(BuildContext context);
typedef ProfileTargetNavigation = void Function(BuildContext context);
typedef ProfileProductNavigation =
    void Function(BuildContext context, String productId);
typedef ProfileCategoryNavigation =
    void Function(BuildContext context, String categoryId);
typedef ProfileStoryNavigation =
    void Function(BuildContext context, Story story);

List<RouteBase> buildProfileRoutes({
  required ProfileDashboardApi profileDashboardApi,
  required CurrentUserProvider currentUserProvider,
  RewardsSummaryApi? rewardsSummaryApi,
  ProfileSettingsNavigation? onOpenSettings,
  ProfileOrderNavigation? onOpenOrderStatus,
  ProfileActivityNavigation? onOpenActivity,
  ProfileTargetNavigation? onOpenRewards,
  ProfileTargetNavigation? onOpenSupport,
  ProfileProductNavigation? onOpenProduct,
  ProfileCategoryNavigation? onOpenCategory,
  ProfileStoryNavigation? onOpenStory,
}) => [
  GoRoute(
    path: profileRoutePath,
    builder: (context, state) => ProfileDashboardPage(
      controller: ProfileDashboardController(
        profileDashboardApi: profileDashboardApi,
        currentUserProvider: currentUserProvider,
      ),
      rewardsSummaryController: rewardsSummaryApi == null
          ? null
          : ProfileRewardsSummaryController(rewardsApi: rewardsSummaryApi),
      onOpenSettings: onOpenSettings == null
          ? null
          : () => onOpenSettings(context),
      onOpenOrderStatus: onOpenOrderStatus == null
          ? null
          : (status) => onOpenOrderStatus(context, status),
      onOpenActivity: onOpenActivity == null
          ? null
          : () => onOpenActivity(context),
      onOpenRewards: onOpenRewards == null
          ? null
          : () => onOpenRewards(context),
      onOpenSupport: onOpenSupport == null
          ? null
          : () => onOpenSupport(context),
      onOpenProduct: onOpenProduct == null
          ? null
          : (productId) => onOpenProduct(context, productId),
      onOpenCategory: onOpenCategory == null
          ? null
          : (categoryId) => onOpenCategory(context, categoryId),
      onOpenStory: onOpenStory == null
          ? null
          : (story) => onOpenStory(context, story),
    ),
  ),
];
