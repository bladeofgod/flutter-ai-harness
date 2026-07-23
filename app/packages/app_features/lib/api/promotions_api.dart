import 'package:app_data/promotions.dart';

/// Flash Sale、Live 和 Story 页面共同消费的窄只读边界。
abstract interface class PromotionsApi {
  Future<PromotionsOverview> loadOverview();

  Future<StorySequence> loadStory(String storyId);
}
