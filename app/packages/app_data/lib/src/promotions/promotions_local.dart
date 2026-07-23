import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import 'promotions_failure.dart';
import 'promotions_fixture.dart';
import 'promotions_models.dart';

part 'promotions_mapper.dart';

final class PromotionsLocalDataSource {
  const PromotionsLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<PromotionsOverview> loadOverview() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: PromotionsFixtureHandler.loadOverviewKey),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _PromotionsFixtureMapper.overview(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<StorySequence> loadStory(String storyId) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: PromotionsFixtureHandler.loadStoryKey,
        payload: <String, Object?>{'storyId': storyId},
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _PromotionsFixtureMapper.story(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mapped = PromotionsFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => PromotionsFailureCode.unknownRequest,
      ApiFailureKind.transport => PromotionsFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => PromotionsFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'promotions.unavailable' => PromotionsFailureCode.unavailable,
        'promotions.story_not_found' => PromotionsFailureCode.notFound,
        _ => PromotionsFailureCode.invalidResponse,
      },
    });
    if (failure.stackTrace case final stackTrace?) {
      Error.throwWithStackTrace(mapped, stackTrace);
    }
    throw mapped;
  }
}
