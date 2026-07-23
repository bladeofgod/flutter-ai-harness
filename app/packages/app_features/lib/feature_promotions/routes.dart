import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/promotions_api.dart';
import 'controllers/promotions_controllers.dart';
import 'pages/flash_sale_page.dart';
import 'pages/live_page.dart';
import 'pages/story_page.dart';

const flashSaleRoutePath = '/promotions/flash-sale';
const liveRoutePath = '/live';
const storyRoutePath = '/stories/:storyId';

String storyLocation(String storyId) =>
    '/stories/${Uri.encodeComponent(storyId)}';

typedef PromotionProductNavigation =
    void Function(BuildContext context, String productId);
typedef StoryExitNavigation = void Function(BuildContext context);

/// Promotions 私有页面的公开 Route 工厂；目标导航由根壳显式装配。
List<RouteBase> buildPromotionRoutes({
  required PromotionsApi promotionsApi,
  required PromotionProductNavigation onOpenProduct,
  required StoryExitNavigation onExitStory,
}) => <RouteBase>[
  GoRoute(
    path: flashSaleRoutePath,
    builder: (context, state) => FlashSalePage(
      controller: FlashSaleController(promotionsApi: promotionsApi),
      onOpenProduct: (productId) => onOpenProduct(context, productId),
    ),
  ),
  GoRoute(
    path: liveRoutePath,
    builder: (context, state) => LivePage(
      controller: LiveController(promotionsApi: promotionsApi),
      onOpenProduct: (productId) => onOpenProduct(context, productId),
    ),
  ),
  GoRoute(
    path: storyRoutePath,
    builder: (context, state) {
      final storyId = state.pathParameters['storyId'];
      if (storyId == null || storyId.trim().isEmpty) {
        return const _MissingStoryRoute();
      }
      return StoryPage(
        controller: StoryController(
          promotionsApi: promotionsApi,
          storyId: storyId,
          onFinished: () => onExitStory(context),
        ),
        onClose: () => onExitStory(context),
        onOpenProduct: (productId) => onOpenProduct(context, productId),
      );
    },
  ),
];

final class _MissingStoryRoute extends StatelessWidget {
  const _MissingStoryRoute();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Story not found'));
}
