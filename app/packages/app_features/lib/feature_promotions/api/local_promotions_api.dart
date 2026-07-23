import 'package:app_data/promotions.dart';

import '../../api/promotions_api.dart';

final class LocalPromotionsApi implements PromotionsApi {
  const LocalPromotionsApi({required PromotionsLocalDataSource dataSource})
    : _dataSource = dataSource;

  final PromotionsLocalDataSource _dataSource;

  @override
  Future<PromotionsOverview> loadOverview() => _dataSource.loadOverview();

  @override
  Future<StorySequence> loadStory(String storyId) =>
      _dataSource.loadStory(storyId);
}
